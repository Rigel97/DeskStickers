import AppKit

/// 每张贴纸对应一个窗口控制器，桥接面板生命周期事件与视图控制器。
final class StickerWindowController: NSObject, NSWindowDelegate {

    let panel: StickerPanel
    let viewController: StickerViewController

    init(sticker: Sticker, callbacks: StickerViewController.Callbacks) {
        let style = sticker.effectiveStyle()
        let insets = style.outerInsets
        let paperFrame = sticker.paperFrame
        let windowFrame = CGRect(
            x: paperFrame.minX - insets.left,
            y: paperFrame.minY - insets.bottom,
            width: paperFrame.width + insets.left + insets.right,
            height: paperFrame.height + insets.top + insets.bottom
        )
        panel = StickerPanel(contentRect: windowFrame)
        panel.stickerID = sticker.id
        viewController = StickerViewController(sticker: sticker, callbacks: callbacks)
        super.init()
        panel.contentViewController = viewController
        // 显式锁定窗口尺寸：不受视图 fitting 影响
        panel.setFrame(windowFrame, display: false)
        panel.delegate = self
    }

    func windowDidResignKey(_ notification: Notification) {
        viewController.handleWindowResignedKey()
    }
}
