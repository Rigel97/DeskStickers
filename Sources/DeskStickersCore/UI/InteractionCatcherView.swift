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
    /// 按下/松开反馈（true = 抬起贴纸）。
    var onLift: ((Bool) -> Void)?

    /// 吸附修正后的基准重置：后续 delta 从新 origin 起算，
    /// 否则下一帧会用旧基准覆盖吸附修正。
    func rebaseDragOrigin(to origin: CGPoint) {
        dragWindowOrigin = origin
        // 同步按下时的鼠标基准，保证后续帧的 delta 连续。
        if dragStart != nil {
            dragStart = NSEvent.mouseLocation
        }
    }

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
        onLift?(true)
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
        onLift?(false)
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
