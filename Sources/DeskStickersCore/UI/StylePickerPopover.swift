import AppKit

// MARK: - 风格预览卡片

/// 单个风格预览卡片：真实渲染缩略图 + 名称 + 选中环。
final class StylePreviewCell: NSView {

    var onSelected: (() -> Void)?
    private let previewView = PreviewImageView(frame: .zero)
    private let label = NSTextField(labelWithString: "")
    private var selected = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewView.wantsLayer = true
        addSubview(previewView)
        label.font = NSFont.systemFont(ofSize: 10.5)
        label.alignment = .center
        label.textColor = NSColor.secondaryLabelColor
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(style: StickerStyle, colorIndex: Int, sampleText: String, selected: Bool) {
        let text = sampleText.isEmpty ? "写点什么…" : String(sampleText.prefix(10))
        previewView.image = StickerPreviewRenderer.render(style: style, colorIndex: colorIndex, text: text)
        label.stringValue = style.name
        self.selected = selected
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let previewHeight = bounds.height - 18
        let inset: CGFloat = 4
        previewView.frame = NSRect(x: inset, y: 0, width: bounds.width - inset * 2, height: previewHeight - 2)
        label.frame = NSRect(x: 0, y: previewHeight, width: bounds.width, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(roundedRect: previewView.frame.insetBy(dx: -1.5, dy: -1.5), xRadius: 6, yRadius: 6)
            ring.lineWidth = 2.5
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onSelected?()
    }

    /// 按比例绘制的预览图容器。
    final class PreviewImageView: NSView {
        var image: NSImage? {
            didSet { needsDisplay = true }
        }
        override func draw(_ dirtyRect: NSRect) {
            guard let image else { return }
            let ratio = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
            let rect = NSRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2,
                width: size.width, height: size.height
            )
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        }
    }
}

// MARK: - 颜色变体圆点

/// 颜色变点行（用于便利贴等多变体风格）。
final class VariantDotsRow: NSView {

    var onSelected: ((Int) -> Void)?
    private var dots: [NSButton] = []
    private(set) var variants: [ColorVariant] = []
    private(set) var selectedIndex = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(variants: [ColorVariant], selectedIndex: Int) {
        self.variants = variants
        self.selectedIndex = selectedIndex
        dots.forEach { $0.removeFromSuperview() }
        dots.removeAll()
        guard variants.count > 1 else {
            needsLayout = true
            needsDisplay = true
            return
        }
        for (index, variant) in variants.enumerated() {
            let button = FirstMouseButton()
            button.bezelStyle = .texturedRounded
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = variant.top.cgColor
            button.layer?.cornerRadius = 7
            button.layer?.borderWidth = index == selectedIndex ? 2.5 : 1
            button.layer?.borderColor = (index == selectedIndex
                ? NSColor.controlAccentColor
                : NSColor(calibratedWhite: 0, alpha: 0.25)).cgColor
            button.tag = index
            button.action = #selector(dotTapped(_:))
            button.target = self
            addSubview(button)
            dots.append(button)
        }
        needsLayout = true
    }

    @objc private func dotTapped(_ sender: NSButton) {
        selectedIndex = sender.tag
        onSelected?(sender.tag)
        refreshSelection(selectedIndex)
    }

    func refreshSelection(_ index: Int) {
        selectedIndex = index
        for (i, dot) in dots.enumerated() {
            dot.layer?.borderWidth = i == index ? 2.5 : 1
            dot.layer?.borderColor = (i == index
                ? NSColor.controlAccentColor
                : NSColor(calibratedWhite: 0, alpha: 0.25)).cgColor
        }
    }

    override func layout() {
        super.layout()
        guard !dots.isEmpty else { return }
        let size = CGFloat(14)
        let spacing = CGFloat(10)
        let total = CGFloat(dots.count) * size + CGFloat(dots.count - 1) * spacing
        var x = (bounds.width - total) / 2
        for dot in dots {
            dot.frame = NSRect(x: x, y: (bounds.height - size) / 2, width: size, height: size)
            x += size + spacing
        }
    }

    override var intrinsicContentSize: NSSize {
        dots.isEmpty ? NSSize(width: 0, height: 0) : NSSize(width: 200, height: 20)
    }
}

// MARK: - 风格选择弹窗

/// 悬停工具栏“风格”按钮弹出的选择器：4×2 风格网格 + 变体圆点。
final class StylePickerPopover: NSPopover, NSPopoverDelegate {

    var onSelectStyle: ((Int) -> Void)?
    var onSelectVariant: ((Int) -> Void)?
    var onWillClose: (() -> Void)?

    private let container = FlippedView(frame: NSRect(x: 0, y: 0, width: 406, height: 236))
    private var cells: [StylePreviewCell] = []
    private let dotsRow = VariantDotsRow(frame: .zero)
    private var currentStyleIndex = 0
    private var currentColorIndex = 0
    private var sampleText = ""

    override init() {
        super.init()
        behavior = .transient
        delegate = self
        contentViewController = NSViewController(nibName: nil, bundle: nil)
        contentViewController?.view = container
        buildGrid()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildGrid() {
        let columns = 4
        let cellSize = CGSize(width: 88, height: 92)
        let spacing = CGFloat(10)
        let margin = CGFloat(13)
        for (index, _) in StickerStyles.all.enumerated() {
            let cell = StylePreviewCell(frame: .zero)
            cell.onSelected = { [weak self] in
                guard let self else { return }
                self.currentStyleIndex = index
                self.onSelectStyle?(index)
                self.refreshCells()
                self.refreshDots()
            }
            container.addSubview(cell)
            cells.append(cell)
            let row = index / columns
            let column = index % columns
            cell.frame = NSRect(
                x: margin + CGFloat(column) * (cellSize.width + spacing),
                y: margin + CGFloat(row) * (cellSize.height + spacing),
                width: cellSize.width, height: cellSize.height
            )
        }
        dotsRow.frame = NSRect(x: 0, y: container.bounds.height - 30, width: container.bounds.width, height: 22)
        container.addSubview(dotsRow)
    }

    func configure(styleIndex: Int, colorIndex: Int, sampleText: String) {
        currentStyleIndex = styleIndex
        currentColorIndex = colorIndex
        self.sampleText = sampleText
        refreshCells()
        refreshDots()
    }

    func refreshSelection(styleIndex: Int, colorIndex: Int) {
        currentStyleIndex = styleIndex
        currentColorIndex = colorIndex
        refreshCells()
        refreshDots()
    }

    private func refreshCells() {
        for (index, cell) in cells.enumerated() {
            let style = StickerStyles.all[index]
            let colorIndex = index == currentStyleIndex ? currentColorIndex : 0
            cell.configure(
                style: style, colorIndex: colorIndex,
                sampleText: sampleText, selected: index == currentStyleIndex
            )
        }
    }

    private func refreshDots() {
        let style = StickerStyles.all[currentStyleIndex]
        dotsRow.configure(variants: style.variants, selectedIndex: currentColorIndex)
        dotsRow.onSelected = { [weak self] index in
            guard let self else { return }
            self.currentColorIndex = index
            self.onSelectVariant?(index)
        }
    }

    func popoverWillClose(_ notification: Notification) {
        onWillClose?()
    }
}
