import Foundation

/// 一张桌面贴纸的持久化模型。
///
/// 坐标使用 AppKit 屏幕坐标系（原点在主屏左下角）。
/// `paperFrame` 指贴纸“纸面”矩形（不含阴影外边距），风格切换时纸面位置保持稳定。
public struct Sticker: Codable, Equatable, Identifiable {
    public var id: UUID
    public var text: String
    public var styleID: String
    /// 风格颜色变体下标（无变体的风格恒为 0）。
    public var colorIndex: Int
    /// 纸面左下角 X（AppKit 全局坐标）。
    public var paperX: Double
    /// 纸面左下角 Y（AppKit 全局坐标）。
    public var paperY: Double
    /// 纸面宽度。高度由文字内容自适应，持久化最近一次计算结果以便恢复。
    public var width: Double
    /// 最近一次计算出的纸面高度（恢复时重新计算，此值仅作断言/兜底）。
    public var height: Double
    /// 整体缩放系数（1.0 = 原始大小）。作用于字号、内边距、阴影与宽高。
    public var scale: Double
    /// 纸面高度覆盖（pt，nil = 高度跟随文字内容自适应）。
    /// 用户拖动底部边缘/角落后固定，右键菜单可恢复自动。
    public var heightOverride: Double?
    /// 字体族覆盖（PostScript 名，nil = 跟随风格）。
    public var fontName: String?
    /// 字号覆盖（pt，nil = 跟随风格与缩放）。
    public var fontSize: Double?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        styleID: String,
        colorIndex: Int = 0,
        paperX: Double,
        paperY: Double,
        width: Double,
        height: Double,
        scale: Double = 1.0,
        heightOverride: Double? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.styleID = styleID
        self.colorIndex = colorIndex
        self.paperX = paperX
        self.paperY = paperY
        self.width = width
        self.height = height
        self.scale = scale
        self.heightOverride = heightOverride
        self.fontName = fontName
        self.fontSize = fontSize
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 实际生效的风格：基础风格按 scale 缩放，再叠加字体/字号覆盖。
    public func effectiveStyle() -> StickerStyle {
        StickerStyles.style(id: styleID).scaled(
            by: CGFloat(scale),
            fontName: fontName,
            fontSize: fontSize.map { CGFloat($0) }
        )
    }

    /// 纸面矩形（AppKit 坐标，原点左下）。
    public var paperFrame: CGRect {
        get { CGRect(x: paperX, y: paperY, width: width, height: height) }
        set {
            paperX = newValue.origin.x
            paperY = newValue.origin.y
            width = newValue.width
            height = newValue.height
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, styleID = "style", colorIndex, paperX, paperY, width, height
        case scale, heightOverride, fontName, fontSize, createdAt, updatedAt
    }

    /// 旧版本状态文件没有 scale/heightOverride/fontName/fontSize 字段，解码时取默认值。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        styleID = try c.decode(String.self, forKey: .styleID)
        colorIndex = try c.decode(Int.self, forKey: .colorIndex)
        paperX = try c.decode(Double.self, forKey: .paperX)
        paperY = try c.decode(Double.self, forKey: .paperY)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        heightOverride = try c.decodeIfPresent(Double.self, forKey: .heightOverride)
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}
