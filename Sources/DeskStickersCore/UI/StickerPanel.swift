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

    /// 解除系统默认的窗口位置钳制。
    ///
    /// NSWindow 在 setFrame / setFrameOrigin 时会调用 constrainFrameRect，
    /// 默认实现把窗口顶边钳到屏幕可见区顶（菜单栏下缘）——但作用在窗口坐标上，
    /// 会把纸面顶边多压低一个外边距，且与吸附/拖动逻辑冲突。
    /// 顶部边界由 ScreenGeometry.clampBelowMenuBar 在纸面坐标上统一执行
    /// （纸面顶边最高 = 菜单栏下缘），这里解除系统钳制让产品逻辑全权负责。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}
