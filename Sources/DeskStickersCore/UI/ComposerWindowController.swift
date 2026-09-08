import AppKit

/// 创建器：输入文字 → 选择风格 → 创建贴纸。
/// 单实例，⌘↩ 创建、Esc 关闭，风格卡片实时预览（真实渲染缩放）。
final class ComposerWindowController: NSObject, NSWindowDelegate {

    var onCreate: ((String, String, Int) -> Void)?
    var onClose: (() -> Void)?

    private let panel: NSPanel
    private let textView = NSTextView(frame: .zero)
    private var cells: [StylePreviewCell] = []
    private let dotsRow = VariantDotsRow(frame: .zero)
    private let createButton = NSButton(title: "创建贴纸", target: nil, action: nil)
    private var selectedStyleIndex = StickerStyles.index(of: "sticky")
    private var selectedColorIndex = 0

    override init() {
        let contentRect = NSRect(x: 0, y: 0, width: 480, height: 468)
        panel = NSPanel(contentRect: contentRect,
                        styleMask: [.titled, .closable],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "新建贴纸"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.delegate = self
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setContentSize(contentRect.size)
        panel.minSize = contentRect.size
        panel.maxSize = contentRect.size
        buildUI()
        refreshCells()
    }

    // MARK: - UI 装配

    private func buildUI() {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size))
        effect.material = .windowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        panel.contentView = effect

        let contentLayoutGuide = effect.safeAreaLayoutGuide

        // 输入区
        let editorCard = NSView(frame: .zero)
        editorCard.wantsLayer = true
        editorCard.layer?.cornerRadius = 10
        editorCard.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.78).cgColor
        editorCard.layer?.borderWidth = 1
        editorCard.layer?.borderColor = NSColor(calibratedWhite: 0, alpha: 0.08).cgColor
        editorCard.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(editorCard)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = ""
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        editorCard.addSubview(scrollView)

        // 风格网格（4 × 2）
        let gridHolder = FlippedView(frame: .zero)
        gridHolder.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(gridHolder)
        let cellSize = CGSize(width: 100, height: 96)
        let spacing = CGFloat(10)
        for (index, _) in StickerStyles.all.enumerated() {
            let cell = StylePreviewCell(frame: .zero)
            cell.onSelected = { [weak self] in
                guard let self else { return }
                self.selectedStyleIndex = index
                self.selectedColorIndex = 0
                self.refreshCells()
                self.refreshDots()
            }
            gridHolder.addSubview(cell)
            cells.append(cell)
            let row = index / 4
            let column = index % 4
            cell.frame = NSRect(
                x: CGFloat(column) * (cellSize.width + spacing),
                y: CGFloat(row) * (cellSize.height + spacing),
                width: cellSize.width, height: cellSize.height
            )
        }

        // 变体圆点
        dotsRow.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(dotsRow)

        // 底部
        let hint = NSTextField(labelWithString: "⌘↩ 创建 · Esc 关闭 · 创建后可拖到任意位置")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hint)

        let cancelButton = NSButton(title: "关闭", target: self, action: #selector(cancelAction))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(cancelButton)

        createButton.bezelStyle = .push
        createButton.controlSize = .large
        createButton.keyEquivalent = "\r"
        createButton.keyEquivalentModifierMask = .command
        createButton.actionTarget(self, action: #selector(createAction))
        createButton.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(createButton)

        NSLayoutConstraint.activate([
            editorCard.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: 14),
            editorCard.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 16),
            editorCard.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -16),
            editorCard.heightAnchor.constraint(equalToConstant: 118),

            scrollView.topAnchor.constraint(equalTo: editorCard.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: editorCard.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: editorCard.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: editorCard.bottomAnchor, constant: -8),

            gridHolder.topAnchor.constraint(equalTo: editorCard.bottomAnchor, constant: 14),
            gridHolder.leadingAnchor.constraint(equalTo: editorCard.leadingAnchor),
            gridHolder.trailingAnchor.constraint(equalTo: editorCard.trailingAnchor),
            gridHolder.heightAnchor.constraint(equalToConstant: cellSize.height * 2 + spacing),

            dotsRow.topAnchor.constraint(equalTo: gridHolder.bottomAnchor, constant: 6),
            dotsRow.leadingAnchor.constraint(equalTo: gridHolder.leadingAnchor),
            dotsRow.trailingAnchor.constraint(equalTo: gridHolder.trailingAnchor),
            dotsRow.heightAnchor.constraint(equalToConstant: 24),

            hint.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 18),
            hint.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -20),

            createButton.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -16),
            createButton.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -12),
            cancelButton.trailingAnchor.constraint(equalTo: createButton.leadingAnchor, constant: -10),
            cancelButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
        ])
    }

    private func refreshCells() {
        for (index, cell) in cells.enumerated() {
            let style = StickerStyles.all[index]
            let colorIndex = index == selectedStyleIndex ? selectedColorIndex : 0
            cell.configure(
                style: style, colorIndex: colorIndex,
                sampleText: currentSampleText(), selected: index == selectedStyleIndex
            )
        }
    }

    private func refreshDots() {
        let style = StickerStyles.all[selectedStyleIndex]
        dotsRow.configure(variants: style.variants, selectedIndex: selectedColorIndex)
        dotsRow.onSelected = { [weak self] index in
            guard let self else { return }
            self.selectedColorIndex = index
            self.refreshCells()
        }
    }

    private func currentSampleText() -> String {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "今天也要加油" : String(text.prefix(10))
    }

    // MARK: - 行为

    func show() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    func close() {
        panel.orderOut(nil)
        onClose?()
    }

    @objc private func createAction() {
        let text = textView.string
        let style = StickerStyles.all[selectedStyleIndex]
        let colorIndex = selectedColorIndex
        textView.string = ""
        close()
        onCreate?(text, style.id, colorIndex)
    }

    @objc private func cancelAction() {
        close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }
}

private extension NSButton {
    func actionTarget(_ target: Any?, action: Selector) {
        self.target = target as AnyObject
        self.action = action
    }
}
