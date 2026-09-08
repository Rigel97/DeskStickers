import AppKit
import Foundation

/// 自动化验证桥（仅在 `--automation` 启动参数下安装）。
///
/// 通过 DistributedNotificationCenter 接收指令，无需辅助功能权限即可驱动完整业务流：
/// 创建 / 移动 / 缩放 / 换风格 / 改文字 / 删除 / 隐藏 / 快照 / 状态导出 / 落盘。
/// 通知名约定：com.deskstickers.automation.<action>，userInfo 值均为 String。
final class AutomationBridge: NSObject {

    private static var current: AutomationBridge?
    private unowned let appController: AppController

    static func install(appController: AppController) {
        guard current == nil else { return }
        let bridge = AutomationBridge(appController: appController)
        bridge.registerObservers()
        current = bridge
        Log.info("自动化钩子已启用 (--automation)")
    }

    private init(appController: AppController) {
        self.appController = appController
        super.init()
    }

    private func registerObservers() {
        let center = DistributedNotificationCenter.default()
        let actions: [(String, Selector)] = [
            ("create", #selector(handleCreate)),
            ("move", #selector(handleMove)),
            ("resize", #selector(handleResize)),
            ("setStyle", #selector(handleSetStyle)),
            ("setText", #selector(handleSetText)),
            ("setScale", #selector(handleSetScale)),
            ("setFont", #selector(handleSetFont)),
            ("delete", #selector(handleDelete)),
            ("deleteAll", #selector(handleDeleteAll)),
            ("hideAll", #selector(handleHideAll)),
            ("showAll", #selector(handleShowAll)),
            ("snapshot", #selector(handleSnapshot)),
            ("dump", #selector(handleDump)),
            ("flush", #selector(handleFlush)),
            ("gripDrag", #selector(handleGripDrag)),
        ]
        for (name, selector) in actions {
            center.addObserver(self, selector: selector,
                               name: NSNotification.Name("com.deskstickers.automation.\(name)"),
                               object: nil)
        }
    }

    // MARK: - 工具

    private func info(_ note: Notification) -> [String: String] {
        note.userInfo as? [String: String] ?? [:]
    }

    private func stickerID(_ note: Notification) -> UUID? {
        UUID(uuidString: info(note)["id"] ?? "")
    }

    // MARK: - 处理器

    @objc private func handleCreate(_ note: Notification) {
        let i = info(note)
        let text = i["text"] ?? ""
        let styleID = i["style"] ?? StickerStyles.sticky.id
        let colorIndex = Int(i["colorIndex"] ?? "") ?? 0
        var paperTopLeft: CGPoint?
        if let x = Double(i["x"] ?? ""), let y = Double(i["y"] ?? "") {
            paperTopLeft = CGPoint(x: CGFloat(x), y: CGFloat(y))
        }
        var widthOverride: CGFloat?
        if let w = i["width"].flatMap({ Double($0) }) {
            widthOverride = CGFloat(w)
        }
        appController.createSticker(
            text: text, styleID: styleID, colorIndex: colorIndex,
            paperTopLeftCG: paperTopLeft, paperWidthOverride: widthOverride
        )
        appController.store.persistNow()
    }

    @objc private func handleMove(_ note: Notification) {
        guard let id = stickerID(note),
              let x = Double(info(note)["x"] ?? ""),
              let y = Double(info(note)["y"] ?? "") else { return }
        appController.moveSticker(id: id, toCGTopLeft: CGPoint(x: CGFloat(x), y: CGFloat(y)))
    }

    @objc private func handleResize(_ note: Notification) {
        guard let id = stickerID(note),
              let width = Double(info(note)["width"] ?? "") else { return }
        appController.resizeSticker(id: id, paperWidth: CGFloat(width))
    }

    @objc private func handleSetStyle(_ note: Notification) {
        guard let id = stickerID(note) else { return }
        let i = info(note)
        appController.setStyle(id: id, styleID: i["style"] ?? StickerStyles.sticky.id,
                               colorIndex: Int(i["colorIndex"] ?? "") ?? 0)
    }

    @objc private func handleSetText(_ note: Notification) {
        guard let id = stickerID(note) else { return }
        appController.setText(id: id, text: info(note)["text"] ?? "")
    }

    @objc private func handleSetScale(_ note: Notification) {
        guard let id = stickerID(note),
              let scale = Double(info(note)["scale"] ?? "") else { return }
        appController.setScale(id: id, scale: scale)
    }

    @objc private func handleSetFont(_ note: Notification) {
        guard let id = stickerID(note) else { return }
        let i = info(note)
        let fontName = i["fontName"].flatMap { $0 == "-" ? nil : $0 }
        let fontSize = i["fontSize"].flatMap(Double.init)
        appController.setFont(id: id, fontName: fontName, fontSize: fontSize)
    }

    @objc private func handleDelete(_ note: Notification) {
        guard let id = stickerID(note) else { return }
        appController.deleteSticker(id, animated: false)
    }

    @objc private func handleDeleteAll(_ note: Notification) {
        for sticker in appController.store.stickers {
            appController.deleteSticker(sticker.id, animated: false)
        }
    }

    @objc private func handleHideAll(_ note: Notification) {
        appController.setStickersHidden(true)
    }

    @objc private func handleShowAll(_ note: Notification) {
        appController.setStickersHidden(false)
    }

    @objc private func handleSnapshot(_ note: Notification) {
        guard let id = stickerID(note), let path = info(note)["path"] else { return }
        guard let data = appController.snapshotData(id: id) else {
            Log.warn("快照失败: \(id)")
            return
        }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    @objc private func handleDump(_ note: Notification) {
        guard let path = info(note)["path"] else { return }
        appController.dumpRuntimeState(to: URL(fileURLWithPath: path))
    }

    @objc private func handleFlush(_ note: Notification) {
        appController.store.persistNow()
    }

    // 临时调试动作：通过真实事件路径模拟拖拽缩放手柄。
    @objc private func handleGripDrag(_ note: Notification) {
        guard let id = stickerID(note),
              let dx = Double(info(note)["dx"] ?? ""),
              let controller = appController.panelController(id: id) else {
            Log.warn("gripDrag: 参数错误或找不到贴纸")
            return
        }
        let panel = controller.panel
        let vc = controller.viewController
        let grip = vc.grip
        let canvas = vc.view

        func runloopTick(_ seconds: Double) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        func warp(_ p: CGPoint) {
            // AppKit 底左坐标 → CG 顶左坐标
            let maxY = NSScreen.screens.first?.frame.maxY ?? 0
            CGWarpMouseCursorPosition(CGPoint(x: p.x, y: maxY - p.y))
        }
        func send(_ type: NSEvent.EventType, atScreenPoint p: CGPoint) {
            let locationInWindow = panel.convertFromScreen(NSRect(origin: p, size: .zero)).origin
            guard let event = NSEvent.mouseEvent(
                with: type, location: locationInWindow,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .pressure ? 1 : 0
            ) else { return }
            panel.sendEvent(event)
        }

        // 1) 光标移到目标中心（grip 需先显示；边缘条始终可命中）
        if info(note)["probe"] == "1" {
            // 只移动真实光标到纸面中心,等待真实事件,报告 chrome 状态
            let paperCenter = CGPoint(x: vc.view.bounds.midX, y: vc.view.bounds.midY)
            let inWindow = vc.view.convert(paperCenter, to: nil)
            let onScreen = panel.convertToScreen(NSRect(origin: inWindow, size: .zero)).origin
            warp(onScreen)
            runloopTick(1.0)
            Log.info("gripProbe: 真实光标移到纸面中心后 grip.isHidden=\(grip.isHidden) alpha=\(grip.alphaValue) toolbar.isHidden=\(vc.toolbar.isHidden)")
            return
        }
        let target: NSView
        switch info(note)["target"] {
        case "left": target = vc.leftEdge
        case "right": target = vc.rightEdge
        default: target = grip
        }
        let targetInCanvas = target.frame
        let targetInWindow = canvas.convert(CGPoint(x: targetInCanvas.midX, y: targetInCanvas.midY), to: nil)
        let targetOnScreen = panel.convertToScreen(NSRect(origin: targetInWindow, size: .zero)).origin
        warp(targetOnScreen)
        // 主动喂一个 mouseMoved 让 tracking area 生效
        send(.mouseMoved, atScreenPoint: targetOnScreen)
        runloopTick(0.3)
        if target === grip, info(note)["forceShow"] == "1" {
            // 模拟真实 hover 后 updateChrome 的效果
            grip.isHidden = false
            grip.alphaValue = 1
        }
        Log.info("gripDrag: target=\(type(of: target)) isHidden=\(target.isHidden) alpha=\(target.alphaValue) frame=\(target.frame) 位置=\(targetOnScreen)")

        // 2) 按下 → 拖动 → 松开
        send(.leftMouseDown, atScreenPoint: targetOnScreen)
        runloopTick(0.1)
        let end = CGPoint(x: targetOnScreen.x + CGFloat(dx), y: targetOnScreen.y)
        for i in 1...10 {
            let p = CGPoint(x: targetOnScreen.x + (end.x - targetOnScreen.x) * CGFloat(i) / 10, y: targetOnScreen.y)
            warp(p)
            send(.leftMouseDragged, atScreenPoint: p)
            runloopTick(0.03)
        }
        send(.leftMouseUp, atScreenPoint: end)
        runloopTick(0.2)
        Log.info("gripDrag: 结束 window=\(panel.frame)")
        appController.store.persistNow()
    }
}
