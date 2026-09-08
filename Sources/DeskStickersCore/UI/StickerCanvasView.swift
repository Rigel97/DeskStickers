import AppKit

/// 贴纸画布：绘制风格背景与占位文案，管理子视图布局，处理精确命中测试。
final class StickerCanvasView: NSView {

    var style: StickerStyle = StickerStyles.sticky
    var colorIndex: Int = 0

    /// 空文字且未进入编辑时显示的占位文案（nil 表示不显示）。
    var placeholderText: String?

    /// 编辑态中允许从内边距区域拖动窗口。
    var allowsPaddingDrag = false
    var onPaddingDrag: ((NSPoint) -> Void)?
    var onPaddingDragEnded: (() -> Void)?

    private var hoverHandler: ((Bool) -> Void)?
    private var dragStart: CGPoint?
    private var dragWindowOrigin: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - 布局

    /// 纸面矩形（画布坐标 = 窗口内容坐标）。
    var paperRect: CGRect {
        let insets = style.outerInsets
        return CGRect(
            x: insets.left,
            y: insets.top,
            width: max(1, bounds.width - insets.left - insets.right),
            height: max(1, bounds.height - insets.top - insets.bottom)
        )
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let paper = paperRect
        if let cg = NSGraphicsContext.current?.cgContext {
            style.drawPaper(in: cg, paperRect: paper, colorIndex: colorIndex)
        }

        if let placeholder = placeholderText {
            let textRect = CGRect(
                x: paper.minX + style.textInsets.left,
                y: paper.minY + style.textInsets.top,
                width: style.textWidth(forPaperWidth: paper.width),
                height: max(1, paper.height - style.textInsets.top - style.textInsets.bottom)
            )
            let attributes = StickerTextEngine.attributes(for: style, colorIndex: colorIndex)
            var dimmed = attributes
            dimmed[.foregroundColor] = style.variant(colorIndex).ink.withAlphaComponent(0.35)
            NSAttributedString(string: placeholder, attributes: dimmed).draw(in: textRect)
        }
    }

    // MARK: - 命中测试：透明边缘放行点击

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let result = super.hitTest(point) else { return nil }
        if result === self {
            let tolerance: CGFloat = 2
            return paperRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) ? self : nil
        }
        return result
    }

    // MARK: - 悬停

    func setHoverHandler(_ handler: ((Bool) -> Void)?) {
        hoverHandler = handler
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { hoverHandler?(true) }
    override func mouseExited(with event: NSEvent) { hoverHandler?(false) }

    // MARK: - 编辑态下的内边距拖动

    override func mouseDown(with event: NSEvent) {
        guard allowsPaddingDrag, let window = window else { return }
        dragStart = NSEvent.mouseLocation
        dragWindowOrigin = window.frame.origin
        window.orderFront(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = dragWindowOrigin else { return }
        let current = NSEvent.mouseLocation
        let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
        onPaddingDrag?(CGPoint(x: origin.x + delta.x, y: origin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil {
            dragStart = nil
            dragWindowOrigin = nil
            onPaddingDragEnded?()
        }
    }
}
