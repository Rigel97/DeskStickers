import AppKit

/// 贴纸窗口：无边框、不激活应用、悬浮于普通窗口之上、跨 Space 常驻。
final class StickerPanel: NSPanel {
    var stickerID: UUID?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        stickerID = nil
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false              // 阴影由画布自绘，避免矩形重影
        isMovable = false              // 拖动由交互层接管
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false // 编辑时需要立即成为 key window
        isReleasedWhenClosed = false   // 生命周期由控制器管理
        title = "Sticker"
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
