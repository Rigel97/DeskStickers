import AppKit

/// 贴纸文字视图：非激活面板中的第一响应者，支持 Esc/⌘↩ 提交、空文案占位。
final class StickerTextView: NSTextView {

    var onEscape: (() -> Void)?
    var onSubmit: (() -> Void)?
    /// 编辑态空文案时显示的占位（沿用当前字体）。
    var placeholder: String?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let placeholder = placeholder, let style = placeholderAttributes {
            NSAttributedString(string: placeholder, attributes: style).draw(in: bounds)
        }
    }

    private var placeholderAttributes: [NSAttributedString.Key: Any]? {
        guard let font = font, let color = textColor else { return nil }
        return [.font: font, .foregroundColor: color.withAlphaComponent(0.35)]
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            onEscape?()
            return
        }
        if selector == #selector(insertNewline(_:)) {
            // ⌘↩ / ⌥↩ = 结束编辑（与创建器 ⌘↩ 创建一致）；
            // 普通 ↩ 仍插入换行（多行文本是贴纸的核心场景）。
            if let event = NSApp.currentEvent,
               event.modifierFlags.intersection([.command, .option]).isEmpty == false {
                onSubmit?()
                return
            }
        }
        super.doCommand(by: selector)
    }
}
