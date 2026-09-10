import AppKit

/// 应用控制器：NSApplication 代理 + 贴纸协调器。
///
/// 职责边界：菜单/状态栏装配在 AppMenu.swift（AppMenuFactory / StatusItemController），
/// 运行时状态导出在 RuntimeStateDumper.swift——本类只保留贴纸生命周期协调。
final class AppController: NSObject, NSApplicationDelegate, AppMenuActions {

    static let shared = AppController()

    let store: StickerStore
    let statusItem = StatusItemController()
    private var controllers: [UUID: StickerWindowController] = [:]
    private var composer: ComposerWindowController?
    private var globalHotkeys: [GlobalHotkeyCenter] = []
    /// 拖动吸附的对齐参考线覆盖窗口（懒创建，全局唯一）。
    private lazy var alignmentGuideWindow = AlignmentGuideWindow()

    override private init() {
        // --state-dir <path>：覆盖状态目录（自动化/e2e 用真实隔离目录——
        // NSHomeDirectory() 不遵循 HOME 环境变量，仅靠 HOME 无法隔离状态文件）。
        store = StickerStore(directory: AppController.stateDirectoryOverride())
        super.init()
    }

    private static func stateDirectoryOverride() -> URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--state-dir"), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[index + 1])
    }

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        installUncaughtExceptionHandler()
        Log.info("桌面贴纸启动 (stickers=\(store.stickers.count), firstLaunch=\(store.isFirstLaunch))")

        restoreStickers()
        statusItem.install(target: self)
        statusItem.updateToggleTitle(allHidden: store.allHidden)
        statusItem.updatePinnedState(pinned: store.pinnedToDesktop)
        statusItem.updateClickThroughState(clickThrough: store.clickThrough)
        statusItem.stickerListProvider = { [weak self] in
            guard let self else { return [] }
            return self.store.stickers.map { sticker in
                let trimmed = sticker.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = trimmed.isEmpty ? "（空贴纸）" : String(trimmed.prefix(18))
                let hiddenMark = (sticker.hidden && !self.store.allHidden) ? " [已隐藏]" : ""
                return StatusItemController.StickerListEntry(
                    id: sticker.id,
                    title: "\(StickerStyles.style(id: sticker.styleID).name) · \(body)\(hiddenMark)"
                )
            }
        }

        // 全局热键在自动化模式下跳过：避免占用系统级组合键干扰 e2e 会话。
        if !CommandLine.arguments.contains("--automation") {
            installGlobalHotkeys()
        }

        if CommandLine.arguments.contains("--automation") {
            AutomationBridge.install(appController: self)
        }

        // 自动化模式完全由分布式通知驱动，不弹任何 UI。
        if store.isFirstLaunch, store.stickers.isEmpty,
           !CommandLine.arguments.contains("--automation") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.openComposer()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.persistNow()
        Log.info("桌面贴纸退出")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openComposer()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 菜单动作（AppMenuActions）

    @objc func newStickerAction() {
        openComposer()
    }

    @objc func newFromClipboardAction() {
        guard let raw = NSPasteboard.general.string(forType: .string) else {
            Log.warn("剪贴板没有可用的文本内容")
            return
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            Log.warn("剪贴板没有可用的文本内容")
            return
        }
        createSticker(text: String(text.prefix(2000)),
                      styleID: StickerStyles.sticky.id, colorIndex: 0)
    }

    @objc func toggleStickersVisibility() {
        setStickersHidden(!store.allHidden)
    }

    @objc func togglePinnedToDesktop() {
        applyPinnedToDesktop(!store.pinnedToDesktop)
    }

    @objc func toggleClickThrough() {
        applyClickThrough(!store.clickThrough)
    }

    @objc func undoAction() {
        performUndo()
    }

    @objc func revealStickerAction(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString) else { return }
        revealSticker(id: id)
    }

    @objc func showAboutAction() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "桌面贴纸 DeskStickers",
            .applicationVersion: "1.0.0",
        ])
    }

    // MARK: - 创建器

    func openComposer() {
        if composer == nil {
            let controller = ComposerWindowController()
            controller.onCreate = { [weak self] text, styleID, colorIndex in
                guard let self else { return }
                let sticker = self.createSticker(text: text, styleID: styleID, colorIndex: colorIndex,
                                                 paperTopLeftCG: nil, paperWidthOverride: nil)
                // 空贴纸创建后直接进入编辑，省掉一次双击（穿透模式下点不到贴纸，跳过）。
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !self.store.allHidden,
                   !self.store.clickThrough,
                   let vc = self.controllers[sticker.id]?.viewController {
                    vc.beginEditing()
                }
            }
            composer = controller
        }
        composer?.show()
    }

    // MARK: - 贴纸协调

    /// 应用级撤销管理器（见 StickerApplication）。编辑文字时 ⌘Z 优先命中
    /// NSTextView 自己的撤销栈，这里的栈只覆盖结构性操作（删除/新建/复制）。
    var undoManager: UndoManager? {
        (NSApp as? StickerApplication)?.stickerUndoManager
    }

    @discardableResult
    func createSticker(text: String, styleID: String, colorIndex: Int,
                       paperTopLeftCG: CGPoint? = nil,
                       paperWidthOverride: CGFloat? = nil,
                       registersUndo: Bool = true) -> Sticker {
        let style = StickerStyles.style(id: styleID)
        let width = paperWidthOverride.map { max(style.minWidth, min(style.maxWidth, $0)) } ?? style.defaultWidth
        let maxHeight = ScreenGeometry.primaryVisibleFrame().height * 0.85
        let height = StickerTextEngine.paperHeight(
            for: text, style: style, colorIndex: colorIndex,
            paperWidth: width, maxHeight: maxHeight
        )

        var paperFrame: CGRect
        if let topLeft = paperTopLeftCG {
            let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
            paperFrame = CGRect(
                x: topLeft.x,
                y: primaryMaxY - topLeft.y - height,
                width: width, height: height
            )
            paperFrame = ScreenGeometry.rescueFrame(paperFrame)
        } else {
            let existing = store.stickers.map { $0.paperFrame }
            let origin = ScreenGeometry.cascadeOrigin(existingFrames: existing, size: CGSize(width: width, height: height))
            paperFrame = CGRect(origin: origin, size: CGSize(width: width, height: height))
        }

        let sticker = Sticker(
            text: text, styleID: style.id, colorIndex: colorIndex,
            paperX: paperFrame.minX, paperY: paperFrame.minY,
            width: paperFrame.width, height: paperFrame.height
        )
        store.upsert(sticker)
        mount(sticker)
        // 创建淡入：贴纸优雅地出现，而不是「啪」地闪现在屏幕上。
        if !store.allHidden, !store.clickThrough,
           let panel = controllers[sticker.id]?.panel, !sticker.hidden {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                panel.animator().alphaValue = 1
            })
        }
        hintStickerChromeIfNeeded()
        if registersUndo {
            registerUndoDelete(sticker.id, actionName: "新建贴纸")
        }
        Log.info("创建贴纸 \(sticker.id) style=\(style.id)")
        return sticker
    }

    /// 注册一条显式分组的撤销项：一次 ⌘Z 恰好撤销一步。
    private func registerUndoAction(name: String, _ body: @escaping (AppController) -> Void) {
        guard let undoManager else { return }
        undoManager.beginUndoGrouping()
        undoManager.setActionName(name)
        undoManager.registerUndo(withTarget: self) { target in body(target) }
        undoManager.endUndoGrouping()
    }

    /// 注册一条「删除该贴纸」的撤销项（新建/复制的反操作）。
    private func registerUndoDelete(_ id: UUID, actionName: String) {
        registerUndoAction(name: actionName) { target in
            target.deleteSticker(id, animated: true)
        }
    }

    private func mount(_ sticker: Sticker) {
        endEditingOthers(except: sticker.id)
        let controller = StickerWindowController(sticker: sticker, callbacks: makeCallbacks())
        controllers[sticker.id] = controller
        presentPanel(of: controller)
    }

    /// 应用全局窗口模式（层级 + 鼠标穿透）并按需显示。
    /// 新建 / 恢复 / 撤销恢复共用，保证穿透与层级状态一致。
    private func presentPanel(of controller: StickerWindowController) {
        let panel = controller.panel
        panel.level = stickerLevel
        panel.ignoresMouseEvents = store.clickThrough
        let stickerHidden = controller.viewController.sticker.hidden
        if !store.allHidden, !stickerHidden {
            panel.alphaValue = store.clickThrough ? Self.clickThroughAlpha : 1
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    /// 贴纸窗口层级：悬浮（默认）或钉在桌面（普通窗口之下）。
    private var stickerLevel: NSWindow.Level {
        store.pinnedToDesktop
            ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            : .floating
    }

    private func makeCallbacks() -> StickerViewController.Callbacks {
        StickerViewController.Callbacks(
            onModelChange: { [weak self] sticker in
                self?.store.upsert(sticker)
            },
            onDelete: { [weak self] sticker in
                self?.deleteSticker(sticker.id)
            },
            onDuplicate: { [weak self] sticker in
                self?.duplicateSticker(sticker.id)
            },
            onInteracted: { [weak self] sticker in
                self?.endEditingOthers(except: sticker.id)
                self?.store.moveToEnd(id: sticker.id)
                self?.controllers[sticker.id]?.panel.orderFront(nil)
            },
            onEditStateChange: { [weak self] sticker, editing in
                if editing {
                    self?.endEditingOthers(except: sticker.id)
                }
            },
            onDragLive: { [weak self] sticker, windowFrame in
                self?.applyDragSnap(stickerID: sticker.id, windowFrame: windowFrame)
            },
            onDragEnded: { [weak self] sticker in
                self?.lastDragOrigins[sticker.id] = nil
                self?.alignmentGuideWindow.hide()
            },
            onToggleHidden: { [weak self] sticker in
                self?.setStickerHidden(id: sticker.id, hidden: !sticker.hidden)
            }
        )
    }

    /// 临时验证开关：定位 e2e 时序问题用。
    static var snapEnabled = true

    /// 拖动过程中每张贴纸上一帧的窗口原点：用于计算本帧拖动方向，
    /// 供吸附引擎做方向感知（离开停靠位不回拉）。拖动结束即清理。
    private var lastDragOrigins: [UUID: CGPoint] = [:]

    /// 拖动过程中的实时吸附：调整窗口原点并展示对齐参考线。
    /// 按住 ⌘ 拖动 = 临时禁用吸附（与其他专业工具的惯例一致）。
    private func applyDragSnap(stickerID: UUID, windowFrame: CGRect) {
        guard let vc = controllers[stickerID]?.viewController else { return }
        let insets = vc.style.outerInsets
        // 统一到纸面坐标系：传入的是窗口 frame，比对目标是其他贴纸的纸面 frame，
        // 不换算的话 insets 偏移（12pt+）会永远盖过吸附阈值。
        func paperFrame(ofWindow frame: CGRect) -> CGRect {
            CGRect(
                x: frame.minX + insets.left,
                y: frame.minY + insets.bottom,
                width: frame.width - insets.left - insets.right,
                height: frame.height - insets.top - insets.bottom
            )
        }
        func windowOrigin(forPaper paper: CGRect) -> CGPoint {
            CGPoint(x: paper.minX - insets.left, y: paper.minY - insets.bottom)
        }

        // 1) 可见顶边界（产品行为，独立于吸附开关与 ⌘）：
        //    纸面顶边不越过相交屏幕的可见区顶（菜单栏/刘海区域不放贴纸）。
        var effectiveWindowFrame = windowFrame
        let proposedPaper = paperFrame(ofWindow: windowFrame)
        let boundedPaper = ScreenGeometry.clampBelowMenuBar(proposedPaper)
        if boundedPaper.origin != proposedPaper.origin {
            let boundedOrigin = windowOrigin(forPaper: boundedPaper)
            controllers[stickerID]?.panel.setFrameOrigin(boundedOrigin)
            // 与吸附修正同理：重置拖动基准，否则下一帧会覆盖钳制。
            vc.catcher.rebaseDragOrigin(to: boundedOrigin)
            vc.canvas.rebaseDragOrigin(to: boundedOrigin)
            lastDragOrigins[stickerID] = boundedOrigin
            effectiveWindowFrame = CGRect(origin: boundedOrigin, size: windowFrame.size)
        }

        // 2) 吸附（可被 ⌘ 临时禁用；顶部边界已在上方执行，不受影响）
        guard !store.clickThrough, Self.snapEnabled else { return }
        // 按住 ⌘ 拖动 = 临时禁用吸附（与其他专业工具的惯例一致）。
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            alignmentGuideWindow.hide()
            return
        }
        let others = store.stickers.compactMap { sticker -> (UUID, CGRect)? in
            guard sticker.id != stickerID, !sticker.hidden else { return nil }
            guard controllers[sticker.id] != nil else { return nil }
            return (sticker.id, sticker.paperFrame)
        }
        let screens = NSScreen.screens.map { $0.visibleFrame }
        let paper = paperFrame(ofWindow: effectiveWindowFrame)
        // 本帧拖动方向：与上一帧（钳制/吸附修正后）的窗口原点相减。
        // 位移过大视为陈旧记录（新一段拖动/瞬移），当作无方向信息处理。
        var dragDelta = CGPoint.zero
        if let previous = lastDragOrigins[stickerID],
           abs(effectiveWindowFrame.minX - previous.x) <= 60,
           abs(effectiveWindowFrame.minY - previous.y) <= 60 {
            dragDelta = CGPoint(x: effectiveWindowFrame.minX - previous.x,
                                y: effectiveWindowFrame.minY - previous.y)
        }
        let result = SnapEngine.snap(windowFrame: paper, movingID: stickerID,
                                     otherStickers: others, screens: screens,
                                     dragDelta: dragDelta)
        let snappedOrigin = windowOrigin(forPaper: CGRect(origin: result.origin, size: paper.size))
        lastDragOrigins[stickerID] = snappedOrigin
        if snappedOrigin != effectiveWindowFrame.origin {
            controllers[stickerID]?.panel.setFrameOrigin(snappedOrigin)
            // 重置拖动基准：后续帧从吸附后的位置起算，避免下一帧覆盖吸附修正。
            controllers[stickerID]?.viewController.catcher.rebaseDragOrigin(to: snappedOrigin)
            controllers[stickerID]?.viewController.canvas.rebaseDragOrigin(to: snappedOrigin)
        }
        if result.guides.isEmpty {
            alignmentGuideWindow.hide()
        } else {
            alignmentGuideWindow.show(guides: result.guides)
        }
    }

    func deleteSticker(_ id: UUID, animated: Bool = true) {
        guard let controller = controllers[id] else {
            store.remove(id: id)
            return
        }
        // 撤销支持：先快照完整模型，⌘Z 时原样恢复（位置/风格/缩放/字体都保留）。
        if let snapshot = store.sticker(id: id) {
            registerUndoAction(name: "删除贴纸") { target in
                target.restoreSticker(snapshot)
            }
        }
        let perform = { [weak self] in
            controller.panel.orderOut(nil)
            self?.controllers[id] = nil
            self?.store.remove(id: id)
        }
        if animated, !store.allHidden {
            let panel = controller.panel
            panel.alphaValue = 1
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                panel.animator().alphaValue = 0
            }, completionHandler: perform)
        } else {
            perform()
        }
        Log.info("删除贴纸 \(id)")
    }

    /// 撤销「删除」：按删除前的完整状态恢复贴纸。
    private func restoreSticker(_ sticker: Sticker) {
        guard controllers[sticker.id] == nil else { return }
        registerUndoAction(name: "恢复贴纸") { target in
            target.deleteSticker(sticker.id, animated: true)
        }
        store.upsert(sticker)
        store.moveToEnd(id: sticker.id)
        mount(sticker)
    }

    // MARK: - 单贴纸隐藏

    /// 隐藏单张贴纸（右键菜单 / 列表）：窗口收起但贴纸保留，可从列表单独召回。
    func setStickerHidden(id: UUID, hidden: Bool) {
        guard var sticker = store.sticker(id: id),
              sticker.hidden != hidden else { return }
        sticker.hidden = hidden
        store.upsert(sticker)
        guard let controller = controllers[id] else { return }
        let panel = controller.panel
        if hidden {
            controller.viewController.endEditing()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        } else if !store.allHidden {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = store.clickThrough ? Self.clickThroughAlpha : 1
            })
        }
        Log.info("单贴纸隐藏 hidden=\(hidden) id=\(id)")
    }

    func duplicateSticker(_ id: UUID) {
        guard let source = store.sticker(id: id) else { return }
        let copy = Sticker(
            text: source.text, styleID: source.styleID, colorIndex: source.colorIndex,
            paperX: source.paperX + 28, paperY: max(ScreenGeometry.primaryVisibleFrame().minY + 20, source.paperY - 28),
            width: source.width, height: source.height,
            scale: source.scale, heightOverride: source.heightOverride,
            fontName: source.fontName, fontSize: source.fontSize,
            hidden: false // 副本直接可见：复制的就是「想要看到的这张」
        )
        store.upsert(copy)
        mount(copy)
        registerUndoDelete(copy.id, actionName: "复制贴纸")
    }

    func endEditingOthers(except id: UUID?) {
        for (key, controller) in controllers where key != id {
            controller.viewController.endEditing()
        }
    }

    // MARK: - 层级与定位

    /// 切换「钉在桌面」模式：悬浮于所有窗口 ↔ 钉在桌面层（普通窗口之下）。
    func applyPinnedToDesktop(_ pinned: Bool) {
        store.setPinnedToDesktop(pinned)
        let level = stickerLevel
        for controller in controllers.values {
            controller.panel.level = level
        }
        statusItem.updatePinnedState(pinned: pinned)
        Log.info("贴纸层级切换 pinnedToDesktop=\(pinned)")
    }

    /// 鼠标穿透模式的提示性不透明度：贴纸仍清晰可读，但一眼可辨「当前不可交互」。
    static let clickThroughAlpha: CGFloat = 0.82

    /// 切换「鼠标穿透」：贴纸保持可见，但鼠标事件（点击/拖动/悬停）全部穿到下层窗口。
    /// 穿透后无法直接点击贴纸本身，需通过状态栏菜单或 ⌥⌘P 全局热键关闭。
    func applyClickThrough(_ enabled: Bool) {
        guard enabled != store.clickThrough else { return }
        store.setClickThrough(enabled)
        for controller in controllers.values {
            controller.viewController.handleClickThroughChanged(enabled: enabled)
            controller.panel.ignoresMouseEvents = enabled
            let panel = controller.panel
            if panel.isVisible {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.18
                    panel.animator().alphaValue = enabled ? Self.clickThroughAlpha : 1
                })
            }
        }
        statusItem.updateClickThroughState(clickThrough: enabled)
        Log.info("鼠标穿透切换 clickThrough=\(enabled)")
    }

    /// 定位贴纸：必要时拯救回屏幕，置前并闪烁提示（状态栏「贴纸列表」点击）。
    func revealSticker(id: UUID) {
        guard let controller = controllers[id] else { return }
        if store.allHidden {
            setStickersHidden(false)
        }
        if controller.viewController.sticker.hidden {
            setStickerHidden(id: id, hidden: false)
        }
        let vc = controller.viewController
        let rescued = ScreenGeometry.rescueFrame(vc.sticker.paperFrame)
        let cg = ScreenGeometry.cgTopLeftRect(rescued)
        vc.movePaperToCGTopLeft(CGPoint(x: cg.minX, y: cg.minY))
        controller.panel.orderFrontRegardless()
        vc.flashPanel(resumeAlpha: store.clickThrough ? Self.clickThroughAlpha : 1)
    }

    func setStickersHidden(_ hidden: Bool) {
        store.setAllHidden(hidden)
        statusItem.updateToggleTitle(allHidden: hidden)
        for controller in controllers.values {
            let panel = controller.panel
            if hidden {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.18
                    panel.animator().alphaValue = 0
                }, completionHandler: { panel.orderOut(nil) })
            } else {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.18
                    panel.animator().alphaValue = store.clickThrough ? Self.clickThroughAlpha : 1
                })
            }
        }
        // 「显示全部」同时清除单贴纸隐藏标记：用户预期是看到所有贴纸，
        // 不应出现“显示了全部却还少一张”的困惑。
        if !hidden {
            for sticker in store.stickers where sticker.hidden {
                var cleared = sticker
                cleared.hidden = false
                store.upsert(cleared)
            }
        }
    }

    // MARK: - 单贴纸变更（菜单 / 自动化共用）

    /// 对某张贴纸执行变更并立即持久化。
    /// setStyle / setText / setScale / setFont / move / resize 共用的透传骨架。
    private func mutate(_ id: UUID, _ body: (StickerViewController) -> Void) {
        guard let controller = controllers[id] else { return }
        body(controller.viewController)
        store.persistNow()
    }

    func setStyle(id: UUID, styleID: String, colorIndex: Int) {
        mutate(id) { $0.applyStyle(styleID: styleID, colorIndex: colorIndex, animated: false) }
    }

    func setScale(id: UUID, scale: Double) {
        mutate(id) { $0.applyPaperScale(scale) }
    }

    func setFont(id: UUID, fontName: String?, fontSize: Double?) {
        mutate(id) { vc in
            if let fontName { vc.applyFontName(fontName) }
            if let fontSize { vc.applyFontSize(fontSize) }
        }
    }

    func setText(id: UUID, text: String) {
        mutate(id) { $0.applyText(text) }
    }

    func moveSticker(id: UUID, toCGTopLeft point: CGPoint) {
        mutate(id) { $0.movePaperToCGTopLeft(point) }
    }

    func resizeSticker(id: UUID, paperWidth: CGFloat) {
        mutate(id) { $0.setPaperWidthExternal(paperWidth) }
    }

    /// 设定纸面高度（nil = 恢复自动高度）。
    func setHeight(id: UUID, height: CGFloat?) {
        mutate(id) { vc in
            if let height {
                vc.setPaperHeightExternal(height)
            } else {
                vc.resetPaperHeightAuto()
            }
        }
    }

    // MARK: - 恢复

    private func restoreStickers() {
        for stored in store.stickers {
            var sticker = stored
            var frame = ScreenGeometry.rescueFrame(sticker.paperFrame)
            if stored.heightOverride == nil {
                // 自动高度模式：按当前字体环境重算（字体缺失等会导致偏差）
                let style = stored.effectiveStyle()
                let maxHeight = ScreenGeometry.primaryVisibleFrame().height * 0.85
                let recomputed = StickerTextEngine.paperHeight(
                    for: sticker.text, style: style, colorIndex: sticker.colorIndex,
                    paperWidth: frame.width, maxHeight: maxHeight
                )
                if abs(recomputed - frame.height) > 1 {
                    frame.origin.y = frame.maxY - recomputed
                    frame.size.height = recomputed
                }
            }
            sticker.paperFrame = frame
            store.upsert(sticker)
            let controller = StickerWindowController(sticker: sticker, callbacks: makeCallbacks())
            controllers[sticker.id] = controller
            presentPanel(of: controller)
        }
        if !store.stickers.isEmpty {
            Log.info("恢复 \(store.stickers.count) 张贴纸")
        }
    }

    // MARK: - 全局快捷键

    /// 注册全局热键（任何应用下可用）。定义集中在 AppHotkeys，菜单展示同源。
    private func installGlobalHotkeys() {
        let definitions: [(definition: GlobalHotkeyDefinition, id: UInt32, handler: () -> Void)] = [
            (definition: AppHotkeys.toggleVisibility, id: 1, handler: { [weak self] in
                guard let self else { return }
                self.setStickersHidden(!self.store.allHidden)
            }),
            (definition: AppHotkeys.toggleClickThrough, id: 2, handler: { [weak self] in
                guard let self else { return }
                self.applyClickThrough(!self.store.clickThrough)
            }),
            (definition: AppHotkeys.newSticker, id: 3, handler: { [weak self] in
                self?.openComposer()
            }),
            (definition: AppHotkeys.undo, id: 4, handler: { [weak self] in
                self?.performUndo()
            }),
            (definition: AppHotkeys.newFromClipboard, id: 5, handler: { [weak self] in
                self?.newFromClipboardAction()
            }),
        ]
        for item in definitions {
            if let center = GlobalHotkeyCenter(definition: item.definition, id: item.id, handler: item.handler) {
                globalHotkeys.append(center)
            } else {
                Log.warn("全局快捷键 \(item.definition.display) 注册失败（可能被其他应用占用）")
            }
        }
        if !globalHotkeys.isEmpty {
            Log.info("全局快捷键已启用: \(globalHotkeys.count) 个")
        }
    }

    // MARK: - 自动化支持

    func snapshotData(id: UUID) -> Data? {
        controllers[id]?.viewController.snapshotPNGData()
    }

    /// 供自动化触发应用级撤销（等价于主菜单「撤销」）。
    func performUndo() {
        undoManager?.undo()
    }

    /// 临时调试辅助：按 id 取窗口控制器。
    func panelController(id: UUID) -> StickerWindowController? {
        controllers[id]
    }

    func dumpRuntimeState(to url: URL) {
        var entries: [RuntimeStateDumper.Entry] = []
        for sticker in store.stickers {
            guard let controller = controllers[sticker.id] else { continue }
            let vc = controller.viewController
            entries.append(RuntimeStateDumper.Entry(
                sticker: sticker,
                paper: vc.paperFrameCG,
                window: vc.windowFrameCG,
                canvasOffset: [vc.style.outerInsets.left,
                               vc.style.outerInsets.top],
                level: Int(controller.panel.level.rawValue),
                visible: controller.panel.isVisible
            ))
        }
        RuntimeStateDumper.write(allHidden: store.allHidden, pinnedToDesktop: store.pinnedToDesktop,
                                 clickThrough: store.clickThrough, entries: entries, to: url)
    }

    // MARK: - Chrome 可发现性提示

    /// 新建贴纸后首次出现悬停控件前，让 grip 短暂可见一下，
    /// 提示「贴纸可以缩放」——只在应用生命周期内做一次，不打扰老用户。
    func hintStickerChromeIfNeeded() {
        guard !Self.didHintChrome else { return }
        Self.didHintChrome = true
        guard !store.clickThrough, !store.allHidden else { return }
        // 依次取最新一张可见贴纸闪烁工具栏
        for controller in controllers.values {
            controller.viewController.flashChromeHint()
            break
        }
    }

    private static var didHintChrome = false
}

extension CGRect: Codable {
    private enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(CGFloat.self, forKey: .x),
            y: try container.decode(CGFloat.self, forKey: .y),
            width: try container.decode(CGFloat.self, forKey: .width),
            height: try container.decode(CGFloat.self, forKey: .height)
        )
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minX, forKey: .x)
        try container.encode(minY, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }
}
