import AppKit

/// 把一张贴纸按真实尺寸离屏渲染成 NSImage。
/// 用途：创建器与风格选择器里的风格预览卡片（先真实渲染再整体缩放，预览 = 真品）。
public enum StickerPreviewRenderer {

    /// 渲染整张贴纸（含外边距与阴影），返回的 image 尺寸为“窗口逻辑尺寸”。
    public static func render(style: StickerStyle, colorIndex: Int, text: String) -> NSImage {
        let paperWidth = min(style.defaultWidth, 200)
        let paperHeight = StickerTextEngine.paperHeight(
            for: text.isEmpty ? "示例" : text,
            style: style, colorIndex: colorIndex,
            paperWidth: paperWidth, maxHeight: .greatestFiniteMagnitude
        )
        let insets = style.outerInsets
        let totalSize = NSSize(
            width: paperWidth + insets.left + insets.right,
            height: paperHeight + insets.top + insets.bottom
        )

        let scale: CGFloat = 2
        let pixelWidth = Int(totalSize.width * scale)
        let pixelHeight = Int(totalSize.height * scale)
        guard let cg = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: totalSize) }

        // 翻转成“左上原点”坐标，并告知 AppKit 该上下文为翻转坐标系（文字才不会倒置）。
        cg.translateBy(x: 0, y: CGFloat(pixelHeight))
        cg.scaleBy(x: scale, y: -scale)

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(cgContext: cg, flipped: true)
        NSGraphicsContext.current = context

        let paper = CGRect(x: insets.left, y: insets.top, width: paperWidth, height: paperHeight)
        // 与 StickerCanvasView 走同一个绘制入口（纸面局部坐标系 + CTM 平移）。
        style.drawPaper(in: cg, paperRect: paper, colorIndex: colorIndex)

        let textRect = CGRect(
            x: paper.minX + style.textInsets.left,
            y: paper.minY + style.textInsets.top,
            width: style.textWidth(forPaperWidth: paperWidth),
            height: max(1, paper.height - style.textInsets.top - style.textInsets.bottom)
        )
        let attributed = StickerTextEngine.attributed(
            text.isEmpty ? "示例" : text, style: style, colorIndex: colorIndex
        )
        attributed.draw(in: textRect)

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cg.makeImage() else { return NSImage(size: totalSize) }
        let image = NSImage(cgImage: cgImage, size: totalSize)
        return image
    }
}

/// 翻转坐标系的普通视图（用于自上而下排布的容器）。
open class FlippedView: NSView {
    override public var isFlipped: Bool { true }
}
