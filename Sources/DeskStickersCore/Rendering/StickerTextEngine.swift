import AppKit

/// 贴纸文字排版与测量。
/// 真实 NSTextView 与离屏测量共用同一套配置，保证高度自适应完全一致。
public enum StickerTextEngine {

    public static let placeholder = "双击输入文字…"

    // MARK: 属性

    public static func paragraphStyle(for style: StickerStyle) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        if let minLineHeight = style.paragraph.minimumLineHeight {
            p.minimumLineHeight = minLineHeight
            p.maximumLineHeight = minLineHeight
        } else {
            p.lineHeightMultiple = style.paragraph.lineHeightMultiple
        }
        return p
    }

    public static func attributes(for style: StickerStyle, colorIndex: Int) -> [NSAttributedString.Key: Any] {
        [
            .font: style.font,
            .foregroundColor: style.variant(colorIndex).ink,
            .paragraphStyle: paragraphStyle(for: style),
            .kern: NSNumber(value: Float(style.paragraph.kern)),
        ]
    }

    public static func attributed(_ text: String, style: StickerStyle, colorIndex: Int) -> NSAttributedString {
        NSAttributedString(string: text, attributes: attributes(for: style, colorIndex: colorIndex))
    }

    /// 把整套风格属性应用到既有文本（换风格时保留文字内容）。
    public static func apply(to storage: NSTextStorage, style: StickerStyle, colorIndex: Int) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(attributes(for: style, colorIndex: colorIndex), range: full)
        storage.endEditing()
    }

    // MARK: 测量

    /// 纯文字高度（不含纸面内边距）。
    public static func measuredTextHeight(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        guard attributed.length > 0 else { return 0 }
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        let glyphRange = layoutManager.glyphRange(for: container)
        let used = layoutManager.usedRect(for: container)
        guard glyphRange.length > 0 else { return attributed.size().height }
        return ceil(used.height) + 1
    }

    /// 自适应纸面高度 = 文字高度 + 上下内边距，约束到 [min, max]。
    public static func paperHeight(for text: String, style: StickerStyle, colorIndex: Int,
                                    paperWidth: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let textWidth = style.textWidth(forPaperWidth: paperWidth)
        let attributed = attributed(text, style: style, colorIndex: colorIndex)
        let textHeight = measuredTextHeight(attributed, width: textWidth)
        var height = textInsetsTotal(style) + textHeight
        height = max(height, style.minHeight(forTextHeight: textHeight))
        height = min(height, maxHeight)
        return ceil(height)
    }

    public static func textInsetsTotal(_ style: StickerStyle) -> CGFloat {
        style.textInsets.top + style.textInsets.bottom
    }

    // MARK: TextView 配置

    /// 以与测量引擎完全一致的方式配置 NSTextView。
    public static func configure(_ textView: NSTextView, style: StickerStyle, colorIndex: Int) {
        textView.isRichText = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.usesFontPanel = false
        textView.allowsImageEditing = false
        textView.backgroundColor = .clear
        textView.textStorage?.setAttributes(attributes(for: style, colorIndex: colorIndex),
                                            range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        textView.typingAttributes = attributes(for: style, colorIndex: colorIndex)
    }
}
