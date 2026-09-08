import AppKit

/// 菜单与状态栏的动作协议：菜单工厂只依赖动作，不依赖具体控制器类型。
@objc protocol AppMenuActions: NSObjectProtocol {
    @objc func newStickerAction()
    @objc func toggleStickersVisibility()
    @objc func showAboutAction()
}

/// 主菜单 + 状态栏图标的构建与更新。
///
/// 从 AppController 拆出：菜单结构、状态项装配与标题刷新属于纯粹的 UI 装配，
/// 不应与贴纸协调逻辑混在同一个类里。
enum AppMenuFactory {

    /// 构建主菜单。返回 (菜单, 需要随隐藏状态刷新标题的菜单项)。
    static func makeMainMenu(target: AppMenuActions) -> (NSMenu, NSMenuItem) {
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
        let toggleItem = NSMenuItem(
            title: "显示/隐藏全部贴纸",
            action: #selector(AppMenuActions.toggleStickersVisibility),
            keyEquivalent: "\\"
        )
        stickerMenu.addItem(toggleItem)
        stickerMenuItem.submenu = stickerMenu
        mainMenu.addItem(stickerMenuItem)

        return (mainMenu, toggleItem)
    }
}

/// 状态栏图标 + 菜单：负责装配与「显示/隐藏」标题刷新。
final class StatusItemController {

    private var statusItem: NSStatusItem?
    private var mainMenuToggleItem: NSMenuItem?

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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "显示/隐藏全部贴纸", action: #selector(AppMenuActions.toggleStickersVisibility), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "关于桌面贴纸", action: #selector(AppMenuActions.showAboutAction), keyEquivalent: "")
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// 绑定主菜单里的「显示/隐藏」项，使其标题随状态同步刷新。
    func bindMainMenuToggle(_ item: NSMenuItem) {
        mainMenuToggleItem = item
    }

    /// 按当前隐藏状态刷新所有「显示/隐藏」标题。
    func updateToggleTitle(allHidden: Bool) {
        let title = allHidden ? "显示全部贴纸" : "隐藏全部贴纸"
        mainMenuToggleItem?.title = title
        if let menu = statusItem?.menu {
            menu.items
                .first { $0.action == #selector(AppMenuActions.toggleStickersVisibility) }?
                .title = title
        }
    }
}
