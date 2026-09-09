import AppKit

/// 应用子类：暴露应用级撤销管理器。
///
/// NSResponder.undo(_:) 会沿响应链取 self.undoManager——
/// 覆写这里之后，主菜单「撤销 / 重做」无需额外接线即可生效，
/// 编辑贴纸文字时仍优先命中 NSTextView 自己的撤销栈。
final class StickerApplication: NSApplication {
    let stickerUndoManager = UndoManager()
    override var undoManager: UndoManager? { stickerUndoManager }

    override init() {
        super.init()
        // 事件循环自动分组在本应用的运行方式下不可靠（分组长期保持打开，
        // 多个操作会落进同一组），改为每个操作显式开组 → 一次 ⌘Z 恰好一步。
        stickerUndoManager.groupsByEvent = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// 应用入口：组装 NSApplication、主菜单与 AppController，然后进入事件循环。
public func main() {
    let app = StickerApplication.shared
    // 桌面常驻工具：不占 Dock 位，也不抢菜单栏焦点（生命周期由状态栏托替）。
    app.setActivationPolicy(.accessory)
    let controller = AppController.shared
    app.delegate = controller
    let handles = AppMenuFactory.makeMainMenu(target: controller)
    app.mainMenu = handles.menu
    controller.statusItem.bindMainMenuToggle(handles.visibilityToggle)
    controller.statusItem.bindPinnedToggle(handles.pinnedToggle)
    controller.statusItem.bindClickThroughToggle(handles.clickThroughToggle)
    app.run()
}
