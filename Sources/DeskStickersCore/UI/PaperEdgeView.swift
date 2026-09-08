import AppKit

/// 纸面左右边缘的隐形缩放区：拖动改变纸面宽度（高度随文字自适应）。
/// 不依赖悬停 chrome 显示，始终参与命中测试——即使 hover 未触发也能缩放。
final class PaperEdgeView: NSView {

    enum Side {
        /// 左缘：向左拖 = 变宽，锚定右缘
        case left
        /// 右缘：向右拖 = 变宽，锚定左缘
        case right
    }

    var side: Side = .right
    /// 拖动过程中的水平位移（向右为正），由控制器换算为新的纸面宽度。
    var onResizeDelta: ((CGFloat) -> Void)?
    var onResizeStart: (() -> Void)?
    var onResizeEnded: (() -> Void)?

    private var dragStartX: CGFloat?
    private var didResize = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        window?.orderFront(nil)
        dragStartX = NSEvent.mouseLocation.x
        didResize = false
        onResizeStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartX else { return }
        let delta = NSEvent.mouseLocation.x - start
        if abs(delta) > 1 { didResize = true }
        onResizeDelta?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        let wasResizing = dragStartX != nil
        dragStartX = nil
        if wasResizing, didResize {
            onResizeEnded?()
        }
    }
}
