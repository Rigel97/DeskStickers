import AppKit

/// 单张贴纸的视图控制器：装配画布/文字/交互层/工具栏，
/// 负责拖动、缩放、编辑状态机、风格切换与模型同步。
final class StickerViewController: NSViewController, NSTextViewDelegate, NSPopoverDelegate {

    struct Callbacks {
        var onModelChange: (Sticker) -> Void = { _ in }
        var onDelete: (Sticker) -> Void = { _ in }
        var onDuplicate: (Sticker) -> Void = { _ in }
        var onInteracted: (Sticker) -> Void = { _ in }
        var onEditStateChange: (Sticker, Bool) -> Void = { _, _ in }
    }

    private(set) var sticker: Sticker
    let callbacks: Callbacks

    let canvas = StickerCanvasView(frame: .zero)
    let scrollView = NSScrollView(frame: .zero)
    let textView = StickerTextView(frame: .zero)
    let catcher = InteractionCatcherView(frame: .zero)
    let leftEdge = PaperEdgeView(frame: .zero)
    let rightEdge = PaperEdgeView(frame: .zero)
    let grip = ResizeGripView(frame: .zero)
    let toolbar = CapsuleToolbar(frame: .zero)

    private(set) var isEditing = false
    private var isPopoverVisible = false
    private var isMouseInside = false
    private var resizeStartPaperWidth: CGFloat?
    private var resizeStartPaperMaxX: CGFloat?
    /// 左缘拖动时锚定右缘（纸面向左生长），其余情况锚定左缘。
    private var resizeAnchorsRight = false
    /// 角落手柄拖动 = 等比缩放（宽高 + 字号）；左右边缘 = 仅调宽。
    private var resizeProportional = false
    private var resizeStartScale: Double = 1.0

    private lazy var stylePopover = StylePickerPopover()

    /// 实际生效风格的缓存：style 在布局/绘制/命中测试路径上被高频访问，
    /// 而派生参数（styleID/scale/字体覆盖）只在 refreshTextAppearance 里变更，
    /// 在那里统一失效即可。
    private var cachedStyle: StickerStyle?

    var style: StickerStyle {
        if let cached = cachedStyle { return cached }
        let computed = sticker.effectiveStyle()
        cachedStyle = computed
        return computed
    }
    var panel: StickerPanel? { view.window as? StickerPanel }

    init(sticker: Sticker, callbacks: Callbacks) {
        self.sticker = sticker
        self.callbacks = callbacks
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - 装配

    override func loadView() {
        // 注意：contentViewController 会让窗口按视图初始尺寸 fit，
        // 因此这里必须用真实的“纸面 + 外边距”尺寸初始化画布。
        let insets = style.outerInsets
        let contentSize = CGSize(
            width: sticker.paperFrame.width + insets.left + insets.right,
            height: sticker.paperFrame.height + insets.top + insets.bottom
        )
        canvas.frame = NSRect(origin: .zero, size: contentSize)
        canvas.autoresizingMask = [.width, .height]
        view = canvas

        canvas.style = style
        canvas.colorIndex = sticker.colorIndex

        // 文字
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.backgroundColor = .clear
        textView.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
        textView.string = sticker.text
        StickerTextEngine.configure(textView, style: style, colorIndex: sticker.colorIndex)
        textView.delegate = self
        textView.onEscape = { [weak self] in self?.endEditing() }
        scrollView.documentView = textView

        // 交互层
        catcher.onDoubleClick = { [weak self] in self?.beginEditing() }
        catcher.onClick = { [weak self] in
            guard let self else { return }
            self.callbacks.onInteracted(self.sticker)
        }
        catcher.onDrag = { [weak self] origin in self?.panel?.setFrameOrigin(origin) }
        catcher.onDragEnded = { [weak self] in self?.commitWindowFrame(interacted: true) }
        catcher.onContextMenu = { [weak self] _ in self?.presentContextMenu() }

        // 缩放手柄（右下角 = 等比缩放：宽高与字号同步变化）
        grip.onResizeDelta = { [weak self] delta in self?.handleResizeDelta(delta) }
        grip.onResizeEnded = { [weak self] in self?.handleResizeEnded() }
        grip.onResizeStart = { [weak self] in self?.handleResizeStart(anchorsRight: false, proportional: true) }

        // 左右边缘缩放区（不依赖悬停，始终可命中，仅调整宽度）
        for (edge, side) in [(leftEdge, PaperEdgeView.Side.left), (rightEdge, PaperEdgeView.Side.right)] {
            edge.side = side
            edge.onResizeStart = { [weak self] in self?.handleResizeStart(anchorsRight: side == .left, proportional: false) }
            edge.onResizeDelta = { [weak self] delta in self?.handleResizeDelta(delta) }
            edge.onResizeEnded = { [weak self] in self?.handleResizeEnded() }
        }

        // 工具栏
        toolbar.onEdit = { [weak self] in
            guard let self else { return }
            if self.isEditing { self.endEditing() } else { self.beginEditing() }
        }
        toolbar.onStyle = { [weak self] in self?.toggleStylePopover() }
        toolbar.onDuplicate = { [weak self] in
            guard let self else { return }
            self.callbacks.onDuplicate(self.sticker)
        }
        toolbar.onDelete = { [weak self] in
            guard let self else { return }
            self.callbacks.onDelete(self.sticker)
        }

        canvas.addSubview(scrollView)
        canvas.addSubview(catcher)
        canvas.addSubview(leftEdge)
        canvas.addSubview(rightEdge)
        canvas.addSubview(grip)
        canvas.addSubview(toolbar)

        canvas.setHoverHandler { [weak self] inside in
            guard let self else { return }
            self.isMouseInside = inside
            self.updateChrome()
        }
        canvas.onPaddingDrag = { [weak self] origin in self?.panel?.setFrameOrigin(origin) }
        canvas.onPaddingDragEnded = { [weak self] in self?.commitWindowFrame(interacted: false) }

        updatePlaceholder()
        updateChrome(initial: true)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSublayersForSticker()
    }

    /// 依据画布 bounds 与风格内边距布局子视图。
    private func layoutSublayersForSticker() {
        guard canvas.bounds.width > 2, canvas.bounds.height > 2 else { return }
        let paper = canvas.paperRect
        let insets = style.textInsets

        let textRect = CGRect(
            x: paper.minX + insets.left,
            y: paper.minY + insets.top,
            width: max(10, paper.width - insets.left - insets.right),
            height: max(10, paper.height - insets.top - insets.bottom)
        )
        scrollView.frame = textRect

        let availableWidth = textRect.width
        let measured = measuredTextHeight()
        let textViewHeight = measured
        textView.frame = NSRect(x: 0, y: 0, width: availableWidth, height: max(textViewHeight, textRect.height))
        textView.textContainer?.size = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
        scrollView.hasVerticalScroller = measured > textRect.height + 1
        scrollView.verticalScroller?.scrollerStyle = .overlay

        catcher.frame = paper
        // 左右边缘缩放条：纸面内侧 7pt，始终可命中（右下角手柄在其上层）
        let edgeThickness: CGFloat = 7
        leftEdge.frame = NSRect(x: paper.minX, y: paper.minY, width: edgeThickness, height: paper.height)
        rightEdge.frame = NSRect(x: paper.maxX - edgeThickness, y: paper.minY, width: edgeThickness, height: paper.height)
        let gripSize: CGFloat = 18
        grip.frame = NSRect(x: paper.maxX - gripSize, y: paper.maxY - gripSize, width: gripSize, height: gripSize)
        let toolbarSize = toolbar.intrinsicContentSize
        toolbar.frame = NSRect(
            x: paper.maxX - toolbarSize.width - 10,
            y: paper.minY - toolbarSize.height / 2,
            width: toolbarSize.width,
            height: toolbarSize.height
        )
    }

    private func measuredTextHeight() -> CGFloat {
        let textWidth = style.textWidth(forPaperWidth: sticker.paperFrame.width)
        let attributed = StickerTextEngine.attributed(sticker.text, style: style, colorIndex: sticker.colorIndex)
        return StickerTextEngine.measuredTextHeight(attributed, width: textWidth)
    }

    // MARK: - 窗口帧换算

    private func windowFrame(forPaperFrame paper: CGRect) -> CGRect {
        let insets = style.outerInsets
        return CGRect(
            x: paper.minX - insets.left,
            y: paper.minY - insets.bottom,
            width: paper.width + insets.left + insets.right,
            height: paper.height + insets.top + insets.bottom
        )
    }

    private func currentPaperFrame() -> CGRect {
        guard let window = view.window else { return sticker.paperFrame }
        let insets = style.outerInsets
        return CGRect(
            x: window.frame.minX + insets.left,
            y: window.frame.minY + insets.bottom,
            width: window.frame.width - insets.left - insets.right,
            height: window.frame.height - insets.top - insets.bottom
        )
    }

    private func setWindowFrame(fromPaperFrame paper: CGRect, animate: Bool) {
        guard let window = view.window else { return }
        let target = windowFrame(forPaperFrame: paper)
        guard window.frame != target else { return }
        if animate {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                context.allowsImplicitAnimation = true
                window.animator().setFrame(target, display: true)
            }, completionHandler: nil)
        } else {
            window.setFrame(target, display: true)
        }
    }

    /// 重新计算纸面高度（顶边锚定），必要时调整窗口。
    func refreshLayout(animate: Bool = false) {
        let oldPaper = sticker.paperFrame
        let maxHeight = maxAllowedPaperHeight()
        let newHeight = StickerTextEngine.paperHeight(
            for: sticker.text, style: style, colorIndex: sticker.colorIndex,
            paperWidth: oldPaper.width, maxHeight: maxHeight
        )
        if abs(newHeight - oldPaper.height) > 0.5 {
            var paper = oldPaper
            paper.size.height = newHeight
            paper.origin.y = oldPaper.maxY - newHeight
            sticker.paperFrame = paper
            setWindowFrame(fromPaperFrame: paper, animate: animate)
        }
        view.needsLayout = true
        canvas.needsDisplay = true
    }

    private func maxAllowedPaperHeight() -> CGFloat {
        let screenFrame = view.window?.screen?.visibleFrame ?? ScreenGeometry.primaryVisibleFrame()
        return max(120, screenFrame.height * 0.85)
    }

    // MARK: - 模型同步

    private func commitModel() {
        callbacks.onModelChange(sticker)
    }

    private func commitWindowFrame(interacted: Bool) {
        sticker.paperFrame = currentPaperFrame()
        commitModel()
        if interacted { callbacks.onInteracted(sticker) }
    }

    // MARK: - 编辑状态机

    func beginEditing() {
        guard !isEditing, let panel = panel else { return }
        isEditing = true
        canvas.placeholderText = nil
        canvas.allowsPaddingDrag = true
        catcher.isHidden = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.placeholder = StickerTextEngine.placeholder
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
        let end = (textView.string as NSString).length
        textView.selectedRange = NSRange(location: end, length: 0)
        toolbar.setEditingState(true)
        updateChrome()
        callbacks.onEditStateChange(sticker, true)
    }

    func endEditing() {
        guard isEditing else { return }
        isEditing = false
        let newText = textView.string
        if newText != sticker.text {
            sticker.text = newText
        }
        textView.isEditable = false
        textView.isSelectable = false
        textView.placeholder = nil
        catcher.isHidden = false
        canvas.allowsPaddingDrag = false
        toolbar.setEditingState(false)
        panel?.makeFirstResponder(nil)
        refreshLayout()
        updatePlaceholder()
        updateChrome()
        commitModel()
        callbacks.onEditStateChange(sticker, false)
    }

    func handleWindowResignedKey() {
        if isEditing, !isPopoverVisible {
            endEditing()
        }
    }

    // MARK: - 文字编辑回调

    func textDidChange(_ notification: Notification) {
        sticker.text = textView.string
        refreshLayout()
        commitModel()
    }

    // MARK: - 外部（自动化 / 上下文菜单）驱动

    func applyText(_ text: String) {
        guard text != sticker.text else { return }
        sticker.text = text
        if let storage = textView.textStorage {
            storage.beginEditing()
            textView.string = text
            StickerTextEngine.apply(to: storage, style: style, colorIndex: sticker.colorIndex)
            storage.endEditing()
        }
        refreshLayout()
        updatePlaceholder()
        commitModel()
    }

    func applyStyle(styleID: String, colorIndex: Int, animated: Bool = true) {
        let base = StickerStyles.style(id: styleID)
        sticker.styleID = base.id
        sticker.colorIndex = max(0, min(colorIndex, base.variants.count - 1))
        refreshTextAppearance(animate: animated)
    }

    /// 切换字体族（nil = 跟随风格默认）。
    func applyFontName(_ name: String?) {
        sticker.fontName = name
        refreshTextAppearance()
    }

    /// 微调字号（pt 覆盖值，nil = 跟随风格与缩放）。
    func applyFontSize(_ size: Double?) {
        sticker.fontSize = size
        refreshTextAppearance()
    }

    /// 当前生效字号基础上增减（clamp 到 9...48）。
    func adjustFontSize(by delta: Double) {
        let next = max(9, min(48, Double(style.fontSize) + delta))
        applyFontSize(next)
    }

    /// 依据最新的 effectiveStyle 重新配置画布与文字外观，并按顶边锚定重排窗口。
    private func refreshTextAppearance(animate: Bool = false, commit: Bool = true) {
        cachedStyle = nil // 派生参数（styleID/scale/字体覆盖）已变，缓存失效
        let current = style
        canvas.style = current
        canvas.colorIndex = sticker.colorIndex
        if let storage = textView.textStorage {
            StickerTextEngine.apply(to: storage, style: current, colorIndex: sticker.colorIndex)
        }
        textView.typingAttributes = StickerTextEngine.attributes(for: current, colorIndex: sticker.colorIndex)
        textView.font = current.font
        textView.textColor = current.variant(sticker.colorIndex).ink
        refreshLayout(animate: animate)
        setWindowFrame(fromPaperFrame: sticker.paperFrame, animate: animate)
        updatePlaceholder()
        if commit { commitModel() }
    }

    /// 移动纸面到指定顶左位置（CG 全局坐标，用于自动化验证）。
    func movePaperToCGTopLeft(_ point: CGPoint) {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        var paper = sticker.paperFrame
        paper.origin.x = point.x
        paper.origin.y = primaryMaxY - point.y - paper.height
        sticker.paperFrame = paper
        setWindowFrame(fromPaperFrame: paper, animate: false)
        commitModel()
    }

    /// 外部设定纸面宽度（保持顶边与左缘锚定）。
    func setPaperWidthExternal(_ width: CGFloat) {
        applyPaperWidth(width, anchorsRight: false)
        commitModel()
    }

    private func applyPaperWidth(_ rawWidth: CGFloat, anchorsRight: Bool) {
        let width = max(style.minWidth, min(style.maxWidth, rawWidth))
        let maxHeight = maxAllowedPaperHeight()
        let height = StickerTextEngine.paperHeight(
            for: sticker.text, style: style, colorIndex: sticker.colorIndex,
            paperWidth: width, maxHeight: maxHeight
        )
        var paper = sticker.paperFrame
        paper.origin.y = paper.maxY - height
        if anchorsRight, let maxX = resizeStartPaperMaxX {
            paper.origin.x = maxX - width
        }
        paper.size = CGSize(width: width, height: height)
        sticker.paperFrame = paper
        setWindowFrame(fromPaperFrame: paper, animate: false)
        view.needsLayout = true
    }

    // MARK: - 拖动 / 缩放手势

    private func handleResizeStart(anchorsRight: Bool, proportional: Bool) {
        resizeStartPaperWidth = sticker.paperFrame.width
        resizeStartPaperMaxX = sticker.paperFrame.maxX
        resizeAnchorsRight = anchorsRight
        resizeProportional = proportional
        resizeStartScale = sticker.scale
    }

    private func handleResizeDelta(_ delta: CGFloat) {
        if resizeProportional {
            // 角落手柄：按拖出的宽度比例缩放整体（字号、内边距、宽高一起变）。
            let startWidth = resizeStartPaperWidth ?? sticker.paperFrame.width
            guard startWidth > 1 else { return }
            let factor = (startWidth + delta) / startWidth
            applyPaperScale(resizeStartScale * Double(factor), anchorsRight: false, commit: false)
        } else {
            let startWidth = resizeStartPaperWidth ?? sticker.paperFrame.width
            let rawWidth = resizeAnchorsRight ? startWidth - delta : startWidth + delta
            applyPaperWidth(rawWidth, anchorsRight: resizeAnchorsRight)
        }
    }

    private func handleResizeEnded() {
        resizeStartPaperWidth = nil
        resizeStartPaperMaxX = nil
        resizeAnchorsRight = false
        resizeProportional = false
        commitModel()
        callbacks.onInteracted(sticker)
    }

    /// 等比缩放：调整 scale 后重算纸面尺寸并同步文字外观。顶边锚定（向下生长/收缩）。
    func applyPaperScale(_ rawScale: Double, anchorsRight: Bool = false, commit: Bool = true) {
        let clamped = max(0.4, min(2.5, rawScale))
        let oldScale = sticker.scale
        sticker.scale = clamped
        let ratio = oldScale > 0.01 ? clamped / oldScale : 1
        if abs(ratio - 1) > 0.001 {
            var paper = sticker.paperFrame
            let oldMaxY = paper.maxY
            paper.size.width = max(60, paper.size.width * ratio)
            paper.origin.y = oldMaxY - paper.size.height
            if anchorsRight, let maxX = resizeStartPaperMaxX {
                paper.origin.x = maxX - paper.size.width
            }
            sticker.paperFrame = paper
        }
        refreshTextAppearance(commit: commit)
    }

    // MARK: - 悬停工具栏

    /// 定位反馈：短暂降低再恢复不透明度，让用户一眼找到这张贴纸。
    func flashPanel() {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0.3
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }, completionHandler: nil)
        })
    }

    private func updateChrome(initial: Bool = false) {
        let visible = isEditing || isMouseInside || isPopoverVisible
        if visible {
            toolbar.isHidden = false
            grip.isHidden = false
        }
        let targetAlpha: CGFloat = visible ? 1 : 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = initial ? 0 : 0.14
            toolbar.animator().alphaValue = targetAlpha
            grip.animator().alphaValue = targetAlpha
        }, completionHandler: {
            if !visible {
                self.toolbar.isHidden = !self.isEditing && !self.isMouseInside && !self.isPopoverVisible
                self.grip.isHidden = self.toolbar.isHidden
            }
        })
    }

    private func updatePlaceholder() {
        canvas.placeholderText = sticker.text.isEmpty ? StickerTextEngine.placeholder : nil
    }

    // MARK: - 风格弹窗

    private func toggleStylePopover() {
        if stylePopover.isShown {
            stylePopover.performClose(nil)
            return
        }
        stylePopover.onSelectStyle = { [weak self] index in
            guard let self else { return }
            self.applyStyle(styleID: StickerStyles.all[index].id, colorIndex: 0)
            self.stylePopover.refreshSelection(styleIndex: index, colorIndex: 0)
        }
        stylePopover.onSelectVariant = { [weak self] colorIndex in
            guard let self else { return }
            self.applyStyle(styleID: self.sticker.styleID, colorIndex: colorIndex, animated: false)
            self.stylePopover.refreshSelection(styleIndex: StickerStyles.index(of: self.sticker.styleID), colorIndex: colorIndex)
        }
        stylePopover.onWillClose = { [weak self] in
            guard let self else { return }
            self.isPopoverVisible = false
            self.updateChrome()
        }
        stylePopover.configure(
            styleIndex: StickerStyles.index(of: sticker.styleID),
            colorIndex: sticker.colorIndex,
            sampleText: sticker.text
        )
        isPopoverVisible = true
        updateChrome()
        stylePopover.show(relativeTo: toolbar.bounds, of: toolbar, preferredEdge: .minY)
    }

    // MARK: - 上下文菜单

    private func presentContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let editItem = NSMenuItem(title: "编辑文字", action: #selector(beginEditingMenuAction), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        let styleItem = NSMenuItem(title: "更换风格", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for (index, style) in StickerStyles.all.enumerated() {
            let item = NSMenuItem(title: style.name, action: #selector(styleMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = style.id == sticker.styleID ? .on : .off
            styleMenu.addItem(item)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        if style.variants.count > 1 {
            let colorItem = NSMenuItem(title: "更换颜色", action: nil, keyEquivalent: "")
            let colorMenu = NSMenu()
            for (index, variant) in style.variants.enumerated() {
                let item = NSMenuItem(title: variant.name, action: #selector(colorMenuAction(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.state = index == sticker.colorIndex ? .on : .off
                colorMenu.addItem(item)
            }
            colorItem.submenu = colorMenu
            menu.addItem(colorItem)
        }

        // 字体族
        let fontItem = NSMenuItem(title: "字体", action: nil, keyEquivalent: "")
        let fontMenu = NSMenu()
        for (index, candidate) in Self.fontCandidates.enumerated() {
            let item = NSMenuItem(title: candidate.title, action: #selector(fontMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = sticker.fontName == candidate.psName ? .on : .off
            fontMenu.addItem(item)
        }
        fontItem.submenu = fontMenu
        menu.addItem(fontItem)

        // 字号
        let sizeItem = NSMenuItem(title: "字号", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        let increase = NSMenuItem(title: "加大", action: #selector(fontSizeIncreaseAction), keyEquivalent: "")
        increase.target = self
        let decrease = NSMenuItem(title: "减小", action: #selector(fontSizeDecreaseAction), keyEquivalent: "")
        decrease.target = self
        let resetSize = NSMenuItem(title: "跟随风格与缩放", action: #selector(fontSizeResetAction), keyEquivalent: "")
        resetSize.target = self
        resetSize.isEnabled = sticker.fontSize != nil
        sizeMenu.addItem(increase)
        sizeMenu.addItem(decrease)
        sizeMenu.addItem(NSMenuItem.separator())
        sizeMenu.addItem(resetSize)
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let duplicateItem = NSMenuItem(title: "复制贴纸", action: #selector(duplicateMenuAction), keyEquivalent: "")
        duplicateItem.target = self
        menu.addItem(duplicateItem)

        menu.addItem(NSMenuItem.separator())

        let deleteItem = NSMenuItem(title: "删除贴纸", action: #selector(deleteMenuAction), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        guard let event = NSApp.currentEvent else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func beginEditingMenuAction() { beginEditing() }
    @objc private func styleMenuAction(_ sender: NSMenuItem) {
        applyStyle(styleID: StickerStyles.all[sender.tag].id, colorIndex: 0)
    }
    @objc private func colorMenuAction(_ sender: NSMenuItem) {
        applyStyle(styleID: sticker.styleID, colorIndex: sender.tag, animated: false)
    }
    @objc private func fontMenuAction(_ sender: NSMenuItem) {
        applyFontName(Self.fontCandidates[sender.tag].psName)
    }
    @objc private func fontSizeIncreaseAction() { adjustFontSize(by: 2) }
    @objc private func fontSizeDecreaseAction() { adjustFontSize(by: -2) }
    @objc private func fontSizeResetAction() { applyFontSize(nil) }
    @objc private func duplicateMenuAction() { callbacks.onDuplicate(sticker) }
    @objc private func deleteMenuAction() { callbacks.onDelete(sticker) }

    /// 右键菜单里可选的字体族（PostScript 名）。
    private static let fontCandidates: [(title: String, psName: String?)] = [
        ("跟随风格", nil),
        ("苹方", "PingFangSC-Regular"),
        ("宋体", "SongtiSC-Regular"),
        ("楷体", "KaitiSC-Regular"),
        ("圆体", "YuantiSC-Regular"),
        ("黑体", "STHeitiSC-Medium"),
        ("等宽", "Menlo-Regular"),
    ]

    // MARK: - 自动化快照

    /// 将画布当前渲染导出为 PNG（1x，不含悬停控件）。
    func snapshotPNGData() -> Data? {
        let chromeWasHidden = toolbar.isHidden
        toolbar.isHidden = true
        grip.isHidden = true
        defer {
            toolbar.isHidden = chromeWasHidden
            grip.isHidden = chromeWasHidden
        }
        let bounds = canvas.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ) else { return nil }
        canvas.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    var windowFrameCG: CGRect {
        guard let window = view.window else { return .zero }
        return ScreenGeometry.cgTopLeftRect(window.frame)
    }

    var paperFrameCG: CGRect {
        ScreenGeometry.cgTopLeftRect(sticker.paperFrame)
    }
}
