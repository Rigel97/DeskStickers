import AppKit

/// 悬停工具栏：编辑 / 风格 / 复制 / 删除 四个操作的胶囊按钮组。
///
/// 视觉规范：深色毛玻璃质感胶囊，hover 时对应按钮提亮，删除按钮 hover 变红
/// （破坏性操作的危险色提示），编辑中「完成」为绿色确认态。
final class CapsuleToolbar: NSView {

    var onEdit: (() -> Void)?
    var onStyle: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onDelete: (() -> Void)?

    private let editButton = FirstMouseButton()
    private let styleButton = FirstMouseButton()
    private let duplicateButton = FirstMouseButton()
    private let deleteButton = FirstMouseButton()
    private var isEditingState = false

    /// 危险操作色（删除 hover）：系统红，保证色盲可辨识（亮度差 + 图标差异）。
    private static let dangerColor = NSColor.systemRed

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.78).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor

        for (button, symbol, action) in [(editButton, "square.and.pencil", #selector(editTapped)),
                                         (styleButton, "paintpalette", #selector(styleTapped)),
                                         (duplicateButton, "plus.square.on.square", #selector(duplicateTapped)),
                                         (deleteButton, "trash", #selector(deleteTapped))] {
            configureButton(button, symbol: symbol, action: action)
        }

        editButton.toolTip = "编辑文字（双击贴纸也可以）"
        styleButton.toolTip = "更换风格与颜色"
        duplicateButton.toolTip = "复制贴纸"
        deleteButton.toolTip = "删除贴纸（⌘Z 可撤销）"

        // hover 反馈：按钮轻提亮；删除按钮变红提示危险
        for button in [editButton, styleButton, duplicateButton] {
            installHoverFeedback(button)
        }
        installHoverFeedback(deleteButton, hovered: Self.dangerColor)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureButton(_ button: FirstMouseButton, symbol: String, action: Selector) {
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = symbol == "trash" ? "×" : "✎"
        }
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.wantsLayer = true // hover 背景高亮依赖 layer
        button.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        button.actionTarget(self, action: action)
        addSubview(button)
    }

    /// hover 高亮：按钮区域跟踪，进入时提亮 tint + 轻背景；删除按钮进入危险色。
    private func installHoverFeedback(_ button: FirstMouseButton, hovered: NSColor? = nil) {
        button.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: ["button": button, "hoveredColor": hovered as Any]
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        guard let info = event.userData as? [String: Any],
              let button = info["button"] as? FirstMouseButton else { return }
        let hoveredColor = (info["hoveredColor"] as? NSColor) ?? NSColor(calibratedWhite: 1, alpha: 1)
        button.layer?.cornerRadius = 5
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            button.animator().contentTintColor = hoveredColor
        })
        button.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.14).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        guard let info = event.userData as? [String: Any],
              let button = info["button"] as? FirstMouseButton else { return }
        let isEditingConfirm = button === editButton && isEditingState
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            button.animator().contentTintColor = isEditingConfirm
                ? NSColor(calibratedRed: 0.42, green: 0.85, blue: 0.62, alpha: 1)
                : NSColor(calibratedWhite: 1, alpha: 0.92)
        })
        button.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        let size = NSSize(width: 28, height: 24)
        let gap: CGFloat = 30
        let buttons = [editButton, styleButton, duplicateButton, deleteButton]
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: 4 + CGFloat(index) * gap, y: (bounds.height - size.height) / 2,
                                  width: size.width, height: size.height)
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 126, height: 26) }

    func setEditingState(_ editing: Bool) {
        isEditingState = editing
        if let image = NSImage(systemSymbolName: editing ? "checkmark" : "square.and.pencil", accessibilityDescription: nil) {
            image.isTemplate = true
            editButton.image = image
        } else {
            editButton.title = editing ? "✓" : "✎"
        }
        editButton.toolTip = editing ? "完成（⌘↩ / Esc）" : "编辑文字（双击贴纸也可以）"
        editButton.contentTintColor = editing
            ? NSColor(calibratedRed: 0.42, green: 0.85, blue: 0.62, alpha: 1)
            : NSColor(calibratedWhite: 1, alpha: 0.92)
    }

    @objc private func editTapped() { onEdit?() }
    @objc private func styleTapped() { onStyle?() }
    @objc private func duplicateTapped() { onDuplicate?() }
    @objc private func deleteTapped() { onDelete?() }
}

/// 支持在应用未激活时响应第一次点击的按钮（贴纸常驻于非激活面板上）。
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension NSButton {
    func actionTarget(_ target: Any?, action: Selector) {
        self.target = target as AnyObject
        self.action = action
    }
}
