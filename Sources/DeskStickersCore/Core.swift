import AppKit

/// 应用入口：组装 NSApplication、主菜单与 AppController，然后进入事件循环。
public func main() {
    let app = NSApplication.shared
    let controller = AppController.shared
    app.delegate = controller
    app.mainMenu = AppController.makeMainMenu()
    app.run()
}
