import AppKit

/// 悬停工具栏：编辑 / 风格 / 删除 三个操作的胶囊按钮组。
final class CapsuleToolbar: NSView {

    var onEdit: (() -> Void)?
    var onStyle: (() -> Void)?
    var onDelete: (() -> Void)?

    private let editButton = FirstMouseButton()
    private let styleButton = FirstMouseButton()
    private let deleteButton = FirstMouseButton()
    private var isEditingState = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.78).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor

        for (button, symbol, action) in [(editButton, "square.and.pencil", #selector(editTapped)),
                                         (styleButton, "paintpalette", #selector(styleTapped)),
                                         (deleteButton, "trash", #selector(deleteTapped))] {
            configureButton(button, symbol: symbol, action: action)
        }

        editButton.toolTip = "编辑文字"
        styleButton.toolTip = "更换风格"
        deleteButton.toolTip = "删除贴纸"
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
        button.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        button.actionTarget(self, action: action)
        addSubview(button)
    }

    override func layout() {
        super.layout()
        let size = NSSize(width: 28, height: 24)
        editButton.frame = NSRect(x: 4, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        styleButton.frame = NSRect(x: 4 + 30, y: editButton.frame.minY, width: size.width, height: size.height)
        deleteButton.frame = NSRect(x: 4 + 60, y: editButton.frame.minY, width: size.width, height: size.height)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 96, height: 26) }

    func setEditingState(_ editing: Bool) {
        isEditingState = editing
        if let image = NSImage(systemSymbolName: editing ? "checkmark" : "square.and.pencil", accessibilityDescription: nil) {
            image.isTemplate = true
            editButton.image = image
        } else {
            editButton.title = editing ? "✓" : "✎"
        }
        editButton.toolTip = editing ? "完成" : "编辑文字"
        editButton.contentTintColor = editing
            ? NSColor(calibratedRed: 0.42, green: 0.85, blue: 0.62, alpha: 1)
            : NSColor(calibratedWhite: 1, alpha: 0.92)
    }

    @objc private func editTapped() { onEdit?() }
    @objc private func styleTapped() { onStyle?() }
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
