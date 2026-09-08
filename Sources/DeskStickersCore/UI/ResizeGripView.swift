import AppKit

/// 右下角缩放手柄：拖动改变纸面宽度（高度随文字自适应）。
final class ResizeGripView: NSView {

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

    override func draw(_ dirtyRect: NSRect) {
        // 两道斜线构成的经典缩放手柄图形
        let color = NSColor(calibratedWhite: 0.35, alpha: 0.55)
        color.setStroke()
        for offset: CGFloat in [5, 10] {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: bounds.width - 4, y: bounds.height - offset))
            path.line(to: CGPoint(x: bounds.width - offset, y: bounds.height - 4))
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.stroke()
        }
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
