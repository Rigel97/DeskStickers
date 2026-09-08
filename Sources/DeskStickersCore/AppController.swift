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

    @objc func toggleStickersVisibility() {
        setStickersHidden(!store.allHidden)
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
                self?.createSticker(text: text, styleID: styleID, colorIndex: colorIndex,
                                    paperTopLeftCG: nil, paperWidthOverride: nil)
            }
            composer = controller
        }
        composer?.show()
    }

    // MARK: - 贴纸协调

    @discardableResult
    func createSticker(text: String, styleID: String, colorIndex: Int,
                       paperTopLeftCG: CGPoint? = nil,
                       paperWidthOverride: CGFloat? = nil) -> Sticker {
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
        Log.info("创建贴纸 \(sticker.id) style=\(style.id)")
        return sticker
    }

    private func mount(_ sticker: Sticker) {
        endEditingOthers(except: sticker.id)
        let controller = StickerWindowController(sticker: sticker, callbacks: makeCallbacks())
        controllers[sticker.id] = controller
        if !store.allHidden {
            controller.panel.orderFrontRegardless()
        }
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
            }
        )
    }

    func deleteSticker(_ id: UUID, animated: Bool = true) {
        guard let controller = controllers[id] else {
            store.remove(id: id)
            return
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

    func duplicateSticker(_ id: UUID) {
        guard let source = store.sticker(id: id) else { return }
        let copy = Sticker(
            text: source.text, styleID: source.styleID, colorIndex: source.colorIndex,
            paperX: source.paperX + 28, paperY: max(ScreenGeometry.primaryVisibleFrame().minY + 20, source.paperY - 28),
            width: source.width, height: source.height,
            scale: source.scale, fontName: source.fontName, fontSize: source.fontSize
        )
        store.upsert(copy)
        mount(copy)
    }

    func endEditingOthers(except id: UUID?) {
        for (key, controller) in controllers where key != id {
            controller.viewController.endEditing()
        }
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
                    panel.animator().alphaValue = 1
                })
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

    // MARK: - 恢复

    private func restoreStickers() {
        for stored in store.stickers {
            var sticker = stored
            var frame = ScreenGeometry.rescueFrame(sticker.paperFrame)
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
            sticker.paperFrame = frame
            store.upsert(sticker)
            let controller = StickerWindowController(sticker: sticker, callbacks: makeCallbacks())
            controllers[sticker.id] = controller
            if !store.allHidden {
                controller.panel.orderFrontRegardless()
            }
        }
        if !store.stickers.isEmpty {
            Log.info("恢复 \(store.stickers.count) 张贴纸")
        }
    }

    // MARK: - 自动化支持

    func snapshotData(id: UUID) -> Data? {
        controllers[id]?.viewController.snapshotPNGData()
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
        RuntimeStateDumper.write(allHidden: store.allHidden, entries: entries, to: url)
    }
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
