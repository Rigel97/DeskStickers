import AppKit

/// 纸面边缘的隐形缩放区：拖动调整纸面尺寸（高度随文字自适应）。
/// 不依赖悬停 chrome 显示，始终参与命中测试——即使 hover 未触发也能缩放。
final class PaperEdgeView: NSView {

    enum Side {
        /// 左缘：向左拖 = 变宽，锚定右缘
        case left
        /// 右缘：向右拖 = 变宽，锚定左缘
        case right
        /// 下缘：向下拖 = 变高，锚定顶边（进入固定高度模式）
        case bottom
    }

    var side: Side = .right
    /// 拖动过程中的位移（屏幕坐标增量，向右/向上为正），由控制器换算为新的纸面尺寸。
    var onResizeDelta: ((CGFloat, CGFloat) -> Void)?
    var onResizeStart: (() -> Void)?
    var onResizeEnded: (() -> Void)?

    private var dragStart: CGPoint?
    private var didResize = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: side == .bottom ? .resizeUpDown : .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        window?.orderFront(nil)
        dragStart = NSEvent.mouseLocation
        didResize = false
        onResizeStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = NSEvent.mouseLocation
        let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
        if abs(delta.x) > 1 || abs(delta.y) > 1 { didResize = true }
        onResizeDelta?(delta.x, delta.y)
    }

    override func mouseUp(with event: NSEvent) {
        let wasResizing = dragStart != nil
        dragStart = nil
        if wasResizing, didResize {
            onResizeEnded?()
        }
    }
}
