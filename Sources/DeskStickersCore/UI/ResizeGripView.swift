import AppKit

/// 右下角缩放手柄：默认拖动自由调整宽高，按住 ⌥ 拖动等比缩放（含字号）。
final class ResizeGripView: NSView {

    /// 拖动过程中的位移（屏幕坐标增量，向右/向上为正）与 ⌥ 修饰键状态，
    /// 由控制器换算为新的纸面尺寸 / 缩放系数。
    var onResizeDelta: ((CGFloat, CGFloat, Bool) -> Void)?
    var onResizeStart: (() -> Void)?
    var onResizeEnded: (() -> Void)?

    private var dragStart: CGPoint?
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
        dragStart = NSEvent.mouseLocation
        didResize = false
        onResizeStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = NSEvent.mouseLocation
        let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
        if abs(delta.x) > 1 || abs(delta.y) > 1 { didResize = true }
        onResizeDelta?(delta.x, delta.y, event.modifierFlags.contains(.option))
    }

    override func mouseUp(with event: NSEvent) {
        let wasResizing = dragStart != nil
        dragStart = nil
        if wasResizing, didResize {
            onResizeEnded?()
        }
    }
}
