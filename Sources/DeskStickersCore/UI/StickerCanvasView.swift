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

    /// 吸附修正后的基准重置（同 InteractionCatcherView.rebaseDragOrigin）。
    /// delta 基于事件位置（无光标竞态），rebase 需同步把事件基准重置为
    /// 最近一次事件位置以恢复增量式语义，避免累计位移叠加波大。
    func rebaseDragOrigin(to origin: CGPoint) {
        dragWindowOrigin = origin
        if let last = lastEventLocation {
            dragStart = last
        }
    }

    /// 拖动反馈：按下时轻微「抬起」贴纸，松手恢复。
    /// 通过画布 layer 的仿射缩放实现，刻意不碰窗口 frame——
    /// 窗口几何在拖动全程保持真实尺寸，拖动结束的 commitWindowFrame
    /// 与吸附计算读到的才是未被放大的值。
    /// （旧实现用 setFrame 把窗口放大 1.02 倍：松手时 frame 已是放大值，
    /// 「×1.0 恢复」在数学上无法复原，导致每拖一次贴纸就永久变大 2%，
    /// 且该错误尺寸会随 commitWindowFrame 写入模型持久化。）
    var isLifted = false {
        didSet {
            guard isLifted != oldValue, let layer = layer else { return }
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let scale: CGFloat = isLifted ? 1.02 : 1.0
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            CATransaction.commit()
        }
    }

    private var hoverHandler: ((Bool) -> Void)?
    private var dragStart: CGPoint?
    private var dragWindowOrigin: CGPoint?
    /// 最近一次 mouseDragged 的事件屏幕位置（rebase 的增量基准）。
    private var lastEventLocation: CGPoint?

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
        dragStart = event.screenLocation
        dragWindowOrigin = window.frame.origin
        window.orderFront(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = dragWindowOrigin else { return }
        let current = event.screenLocation
        lastEventLocation = current
        let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
        onPaddingDrag?(CGPoint(x: origin.x + delta.x, y: origin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil {
            dragStart = nil
            dragWindowOrigin = nil
            lastEventLocation = nil
            onPaddingDragEnded?()
        }
    }
}
