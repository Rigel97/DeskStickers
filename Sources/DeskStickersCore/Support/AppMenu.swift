import AppKit

/// 菜单与状态栏的动作协议：菜单工厂只依赖动作，不依赖具体控制器类型。
@objc protocol AppMenuActions: NSObjectProtocol {
    @objc func newStickerAction()
    @objc func newFromClipboardAction()
    @objc func toggleStickersVisibility()
    @objc func togglePinnedToDesktop()
    @objc func revealStickerAction(_ sender: NSMenuItem)
    @objc func showAboutAction()
}

/// makeMainMenu 返回的、需要随应用状态刷新标题/勾选的菜单项句柄。
struct MainMenuHandles {
    let menu: NSMenu
    /// 「显示/隐藏全部贴纸」：标题随隐藏状态刷新。
    let visibilityToggle: NSMenuItem
    /// 「钉在桌面」：勾选状态随层级模式刷新。
    let pinnedToggle: NSMenuItem
}

/// 主菜单 + 状态栏图标的构建与更新。
///
/// 从 AppController 拆出：菜单结构、状态项装配与标题刷新属于纯粹的 UI 装配，
/// 不应与贴纸协调逻辑混在同一个类里。
enum AppMenuFactory {

    /// 构建主菜单，并返回需要随状态刷新的菜单项句柄。
    static func makeMainMenu(target: AppMenuActions) -> MainMenuHandles {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于桌面贴纸", action: #selector(AppMenuActions.showAboutAction), keyEquivalent: "")
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
        fileMenu.addItem(withTitle: "新建贴纸", action: #selector(AppMenuActions.newStickerAction), keyEquivalent: "n")
        let fromClipboard = NSMenuItem(title: "从剪贴板新建贴纸", action: #selector(AppMenuActions.newFromClipboardAction), keyEquivalent: "V")
        fromClipboard.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(fromClipboard)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        // undo:/redo: 经响应链取 NSApplication.undoManager（见 StickerApplication），
        // 由 NSUndoManager 自动启用/禁用并更新标题。
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
        let toggleItem = NSMenuItem(
            title: "显示/隐藏全部贴纸",
            action: #selector(AppMenuActions.toggleStickersVisibility),
            keyEquivalent: "\\"
        )
        stickerMenu.addItem(toggleItem)
        let pinnedItem = NSMenuItem(
            title: "钉在桌面（不遮挡窗口）",
            action: #selector(AppMenuActions.togglePinnedToDesktop),
            keyEquivalent: ""
        )
        stickerMenu.addItem(pinnedItem)
        stickerMenuItem.submenu = stickerMenu
        mainMenu.addItem(stickerMenuItem)

        return MainMenuHandles(menu: mainMenu, visibilityToggle: toggleItem, pinnedToggle: pinnedItem)
    }
}

/// 状态栏图标 + 菜单：负责装配与「显示/隐藏」「钉在桌面」状态刷新、动态贴纸列表。
final class StatusItemController: NSObject, NSMenuDelegate {

    /// 贴纸列表条目（状态栏子菜单用）。
    struct StickerListEntry {
        let id: UUID
        let title: String
    }

    /// 贴纸列表数据源：每次菜单展开时调用。
    var stickerListProvider: (() -> [StickerListEntry])?

    private var statusItem: NSStatusItem?
    private var mainMenuToggleItem: NSMenuItem?
    private var mainMenuPinnedItem: NSMenuItem?
    private let stickerListMenu = NSMenu()

    /// 安装状态栏图标（幂等）。
    func install(target: AppMenuActions) {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "桌面贴纸") {
                button.image = image
            } else {
                button.title = "贴"
            }
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "新建贴纸", action: #selector(AppMenuActions.newStickerAction), keyEquivalent: "n")
        menu.addItem(withTitle: "从剪贴板新建贴纸", action: #selector(AppMenuActions.newFromClipboardAction), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        let listParent = NSMenuItem(title: "贴纸列表", action: nil, keyEquivalent: "")
        stickerListMenu.delegate = self
        listParent.submenu = stickerListMenu
        menu.addItem(listParent)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "显示/隐藏全部贴纸", action: #selector(AppMenuActions.toggleStickersVisibility), keyEquivalent: "")
        menu.addItem(withTitle: "钉在桌面（不遮挡窗口）", action: #selector(AppMenuActions.togglePinnedToDesktop), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "关于桌面贴纸", action: #selector(AppMenuActions.showAboutAction), keyEquivalent: "")
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // 不设显式 target：action 沿响应链派发（app delegate 在链末尾），
        // terminate: 等系统 action 也能正常命中。
        item.menu = menu
        statusItem = item
    }

    // MARK: - 贴纸列表子菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === stickerListMenu else { return }
        menu.removeAllItems()
        let entries = stickerListProvider?() ?? []
        guard !entries.isEmpty else {
            let empty = NSMenuItem(title: "无贴纸", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for entry in entries {
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(AppMenuActions.revealStickerAction(_:)),
                keyEquivalent: ""
            )
            item.representedObject = entry.id.uuidString
            menu.addItem(item)
        }
    }

    // MARK: - 状态同步

    /// 绑定主菜单里的「显示/隐藏」项，使其标题随状态同步刷新。
    func bindMainMenuToggle(_ item: NSMenuItem) {
        mainMenuToggleItem = item
    }

    /// 绑定主菜单里的「钉在桌面」项，使其勾选状态同步刷新。
    func bindPinnedToggle(_ item: NSMenuItem) {
        mainMenuPinnedItem = item
    }

    /// 按当前隐藏状态刷新所有「显示/隐藏」标题。
    func updateToggleTitle(allHidden: Bool) {
        let title = allHidden ? "显示全部贴纸" : "隐藏全部贴纸"
        mainMenuToggleItem?.title = title
        statusItemMenuTitle(
            action: #selector(AppMenuActions.toggleStickersVisibility),
            title: title
        )
    }

    /// 按当前层级模式刷新「钉在桌面」勾选。
    func updatePinnedState(pinned: Bool) {
        mainMenuPinnedItem?.state = pinned ? .on : .off
        setMenuItemState(
            action: #selector(AppMenuActions.togglePinnedToDesktop),
            state: pinned ? .on : .off
        )
    }

    private func statusItemMenuTitle(action: Selector, title: String) {
        if let item = statusItem?.menu?.items.first(where: { $0.action == action }) {
            item.title = title
        }
    }

    private func setMenuItemState(action: Selector, state: NSControl.StateValue) {
        if let item = statusItem?.menu?.items.first(where: { $0.action == action }) {
            item.state = state
        }
    }
}
