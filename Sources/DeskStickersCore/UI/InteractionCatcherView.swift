import AppKit

/// 非编辑态覆盖在文字之上的交互层：
/// 按住拖动 = 移动窗口；双击 = 进入编辑；右键 = 上下文菜单。
final class InteractionCatcherView: NSView {

    var onDoubleClick: (() -> Void)?
    var onContextMenu: ((NSPoint) -> Void)?
    /// 拖动目标位置（窗口 origin，屏幕坐标）。
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onClick: (() -> Void)?

    private var dragStart: CGPoint?
    private var dragWindowOrigin: CGPoint?
    private var didMove = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        window.orderFront(nil)
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        didMove = false
        dragStart = NSEvent.mouseLocation
        dragWindowOrigin = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = dragWindowOrigin else { return }
        let current = NSEvent.mouseLocation
        let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
        if abs(delta.x) > 3 || abs(delta.y) > 3 {
            didMove = true
            NSCursor.closedHand.set()
        }
        guard didMove else { return }
        onDrag?(CGPoint(x: origin.x + delta.x, y: origin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragStart != nil
        dragStart = nil
        dragWindowOrigin = nil
        NSCursor.openHand.set()
        if wasDragging {
            if didMove {
                onDragEnded?()
            } else {
                onClick?()
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let locationInWindow = event.locationInWindow
        let point = convert(locationInWindow, from: nil)
        onContextMenu?(point)
    }
}
