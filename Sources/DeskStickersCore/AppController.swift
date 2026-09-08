import AppKit

/// 应用控制器：NSApplication 代理 + 贴纸协调器 + 菜单/状态项。
final class AppController: NSObject, NSApplicationDelegate {

    static let shared = AppController()

    let store: StickerStore
    private var controllers: [UUID: StickerWindowController] = [:]
    private var composer: ComposerWindowController?
    private var statusItem: NSStatusItem?
    private var hideToggleMenuItem: NSMenuItem?

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
        setupStatusItem()
        updateHideToggleTitle()

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

    // MARK: - 主菜单

    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于桌面贴纸", action: #selector(showAboutAction), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏桌面贴纸", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出桌面贴纸", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "新建贴纸", action: #selector(newStickerAction), keyEquivalent: "n")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let stickerMenuItem = NSMenuItem()
        let stickerMenu = NSMenu(title: "贴纸")
        stickerMenu.addItem(withTitle: "显示/隐藏全部贴纸", action: #selector(toggleStickersVisibility), keyEquivalent: "\\")
        stickerMenuItem.submenu = stickerMenu
        mainMenu.addItem(stickerMenuItem)

        let shared = AppController.shared
        shared.hideToggleMenuItem = stickerMenu.items.first
        return mainMenu
    }

    // MARK: - 菜单动作

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

    // MARK: - 状态项

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "桌面贴纸") {
                button.image = image
            } else {
                button.title = "贴"
            }
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "新建贴纸", action: #selector(newStickerAction), keyEquivalent: "n")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "显示/隐藏全部贴纸", action: #selector(toggleStickersVisibility), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "关于桌面贴纸", action: #selector(showAboutAction), keyEquivalent: "")
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func updateHideToggleTitle() {
        let title = store.allHidden ? "显示全部贴纸" : "隐藏全部贴纸"
        hideToggleMenuItem?.title = title
        if let menu = statusItem?.menu {
            menu.items
                .first { $0.action == #selector(toggleStickersVisibility) }?
                .title = title
        }
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

    func setStyle(id: UUID, styleID: String, colorIndex: Int) {
        guard let controller = controllers[id] else { return }
        controller.viewController.applyStyle(styleID: styleID, colorIndex: colorIndex, animated: false)
        store.persistNow()
    }

    func setScale(id: UUID, scale: Double) {
        guard let controller = controllers[id] else { return }
        controller.viewController.applyPaperScale(scale)
        store.persistNow()
    }

    func setFont(id: UUID, fontName: String?, fontSize: Double?) {
        guard let controller = controllers[id] else { return }
        if let fontName { controller.viewController.applyFontName(fontName) }
        if let fontSize { controller.viewController.applyFontSize(fontSize) }
        store.persistNow()
    }

    func setText(id: UUID, text: String) {
        guard let controller = controllers[id] else { return }
        controller.viewController.applyText(text)
        store.persistNow()
    }

    func moveSticker(id: UUID, toCGTopLeft point: CGPoint) {
        guard let controller = controllers[id] else { return }
        controller.viewController.movePaperToCGTopLeft(point)
        store.persistNow()
    }

    func resizeSticker(id: UUID, paperWidth: CGFloat) {
        guard let controller = controllers[id] else { return }
        controller.viewController.setPaperWidthExternal(paperWidth)
        store.persistNow()
    }

    func endEditingOthers(except id: UUID?) {
        for (key, controller) in controllers where key != id {
            controller.viewController.endEditing()
        }
    }

    func setStickersHidden(_ hidden: Bool) {
        store.setAllHidden(hidden)
        updateHideToggleTitle()
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
        struct DumpSticker: Codable {
            var id: String
            var text: String
            var style: String
            var colorIndex: Int
            var scale: Double
            var fontName: String?
            var fontSize: Double?
            var paper: CGRect
            var window: CGRect
            /// 纸面在画布（快照）中的偏移，便于像素验证。
            var canvasOffset: [CGFloat]
            var level: Int
            var visible: Bool
        }
        struct Dump: Codable {
            var allHidden: Bool
            var stickers: [DumpSticker]
        }
        var items: [DumpSticker] = []
        for sticker in store.stickers {
            guard let controller = controllers[sticker.id] else { continue }
            let vc = controller.viewController
            items.append(DumpSticker(
                id: sticker.id.uuidString,
                text: sticker.text,
                style: sticker.styleID,
                colorIndex: sticker.colorIndex,
                scale: sticker.scale,
                fontName: sticker.fontName,
                fontSize: sticker.fontSize,
                paper: vc.paperFrameCG,
                window: vc.windowFrameCG,
                canvasOffset: [vc.style.outerInsets.left,
                               vc.style.outerInsets.top],
                level: Int(controller.panel.level.rawValue),
                visible: controller.panel.isVisible
            ))
        }
        let dump = Dump(allHidden: store.allHidden, stickers: items)
        if let data = try? JSONEncoder().encode(dump) {
            try? data.write(to: url)
        }
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
