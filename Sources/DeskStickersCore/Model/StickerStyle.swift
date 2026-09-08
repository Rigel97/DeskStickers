import AppKit

// MARK: - 风格规格类型

/// 阴影规格。offsetY 为视觉向下位移（绘制时适配翻转坐标系）。
public struct ShadowSpec {
    public let color: NSColor
    public let alpha: CGFloat
    public let blur: CGFloat
    public let offsetY: CGFloat

    public init(color: NSColor = .black, alpha: CGFloat, blur: CGFloat, offsetY: CGFloat) {
        self.color = color
        self.alpha = alpha
        self.blur = blur
        self.offsetY = offsetY
    }
}

/// 段落排版规格。
public struct ParagraphSpec {
    /// 行高倍数（与 minimumLineHeight 二选一使用）。
    public let lineHeightMultiple: CGFloat
    /// 最小行高（便签纸用来对齐横线）。
    public let minimumLineHeight: CGFloat?
    /// 字距微调。
    public let kern: CGFloat

    public init(lineHeightMultiple: CGFloat = 1.45, minimumLineHeight: CGFloat? = nil, kern: CGFloat = 0) {
        self.lineHeightMultiple = lineHeightMultiple
        self.minimumLineHeight = minimumLineHeight
        self.kern = kern
    }
}

/// 颜色变体：背景（上/下渐变 + 描边）与墨色。
public struct ColorVariant {
    public let name: String
    public let top: NSColor
    public let bottom: NSColor
    public let ink: NSColor
    public let edge: NSColor?

    public init(name: String, top: NSColor, bottom: NSColor? = nil, ink: NSColor, edge: NSColor? = nil) {
        self.name = name
        self.top = top
        self.bottom = bottom ?? top
        self.ink = ink
        self.edge = edge
    }
}

/// 绘制上下文（画布为翻转坐标系：原点在纸面左上角）。
public struct StickerDrawContext {
    public let paper: CGRect
    public let variant: ColorVariant
    public let colorIndex: Int
    public let textInsets: NSEdgeInsets
    public let shadow: ShadowSpec
}

// MARK: - 风格

/// 一种贴纸风格的完整视觉体系。
public struct StickerStyle {
    public let id: String
    public let name: String
    /// 字体 PostScript 名回退链（优先中文字体，保证中文渲染同样有性格）。
    public let fontNames: [String]
    public let fontSize: CGFloat
    /// 纸面内部文字内边距（上/左/下/右）。
    public let textInsets: NSEdgeInsets
    public let cornerRadius: CGFloat
    public let shadow: ShadowSpec
    /// 纸面之外的额外顶部留白（放装饰物，如胶带）。
    public let extraTopMargin: CGFloat
    public let defaultWidth: CGFloat
    public let minWidth: CGFloat
    public let maxWidth: CGFloat
    public let paragraph: ParagraphSpec
    public let variants: [ColorVariant]
    /// 纸面背景与装饰绘制。
    public let draw: (StickerDrawContext) -> Void

    public var font: NSFont {
        FontBook.font(postScriptNames: fontNames, size: fontSize)
    }

    public func variant(_ index: Int) -> ColorVariant {
        guard !variants.isEmpty else { return ColorVariant(name: "", top: .white, ink: .black) }
        return variants[max(0, min(index, variants.count - 1))]
    }

    /// 在当前 CG 上下文中绘制纸面。
    ///
    /// 风格绘制约定纸面局部坐标系（原点 = 纸面左上角，y 向下），
    /// 本方法负责平移 CTM 并构造绘制上下文——调用方只给纸面矩形，
    /// 不可能再犯「忘记平移导致装饰画到纸面外」的错误。
    ///
    /// - Parameters:
    ///   - cg: 目标上下文（画布或离屏位图均可）。
    ///   - paperRect: 纸面在**当前上下文坐标系**中的矩形。
    public func drawPaper(in cg: CGContext, paperRect: CGRect, colorIndex: Int) {
        let context = StickerDrawContext(
            paper: CGRect(origin: .zero, size: paperRect.size),
            variant: variant(colorIndex),
            colorIndex: colorIndex,
            textInsets: textInsets,
            shadow: shadow
        )
        cg.saveGState()
        cg.translateBy(x: paperRect.minX, y: paperRect.minY)
        draw(context)
        cg.restoreGState()
    }

    /// 纸面四周（窗口内）的留白，用于容纳阴影、装饰与悬停工具栏。
    public var outerInsets: NSEdgeInsets {
        let base = ceil(shadow.blur * 0.55) + 3
        let side = max(base, 12)
        let bottom = max(base + shadow.offsetY, 14)
        // 顶部至少 16pt：悬停工具栏需要跨骑纸面上缘（高 26pt 的一半 + 呼吸空间）
        let top = max(base, 16) + extraTopMargin + max(0, shadow.offsetY * 0.4)
        return NSEdgeInsets(top: top, left: side, bottom: bottom, right: side)
    }

    /// 文字可用宽度。
    public func textWidth(forPaperWidth paperWidth: CGFloat) -> CGFloat {
        max(40, paperWidth - textInsets.left - textInsets.right)
    }

    /// 按系数缩放排版度量（字号、内边距、圆角、阴影、宽高与行距），
    /// 并叠加可选的字体族 / 字号覆盖。视觉装饰按纸面相对坐标绘制，随纸面自然缩放。
    public func scaled(by s: CGFloat, fontName: String? = nil, fontSize: CGFloat? = nil) -> StickerStyle {
        guard s > 0 else { return self }
        var names = fontNames
        if let fontName { names = [fontName] + names }
        return StickerStyle(
            id: id,
            name: name,
            fontNames: names,
            fontSize: fontSize ?? self.fontSize * s,
            textInsets: NSEdgeInsets(
                top: textInsets.top * s,
                left: textInsets.left * s,
                bottom: textInsets.bottom * s,
                right: textInsets.right * s
            ),
            cornerRadius: cornerRadius * s,
            shadow: ShadowSpec(
                color: shadow.color,
                alpha: shadow.alpha,
                blur: shadow.blur * s,
                offsetY: shadow.offsetY * s
            ),
            extraTopMargin: extraTopMargin * s,
            defaultWidth: defaultWidth * s,
            minWidth: minWidth * s,
            maxWidth: maxWidth * s,
            paragraph: ParagraphSpec(
                lineHeightMultiple: paragraph.lineHeightMultiple,
                minimumLineHeight: paragraph.minimumLineHeight.map { $0 * s },
                kern: paragraph.kern * s
            ),
            variants: variants,
            draw: draw
        )
    }

    /// 最小纸面高度（约两行文字 + 上下留白）。
    public func minHeight(forTextHeight textHeight: CGFloat) -> CGFloat {
        textInsets.top + textInsets.bottom + max(textHeight, fontSize * 2.4)
    }
}

// MARK: - 内置风格注册表

/// 8 种内置风格。每种都有独立的字体体系、背景体系、装饰体系与阴影。
public enum StickerStyles {

    public static let all: [StickerStyle] = [
        notebook, handwritten, sticky, minimal, vintage, blackboard, cute, mono
    ]

    /// id → 风格 的字典缓存（style(id:) 在布局/绘制路径上被高频调用）。
    private static let byID: [String: StickerStyle] = {
        var map: [String: StickerStyle] = [:]
        for style in all { map[style.id] = style }
        return map
    }()

    public static func style(id: String) -> StickerStyle {
        byID[id] ?? sticky
    }

    public static func index(of id: String) -> Int {
        if let index = all.firstIndex(where: { $0.id == id }) { return index }
        return all.firstIndex { $0.id == sticky.id } ?? 0
    }

    // MARK: 1. 便签纸 —— 白纸、红边线、淡蓝横线，日常钢笔字
    public static let notebook = StickerStyle(
        id: "notebook",
        name: "便签纸",
        fontNames: ["HiraginoSansGB-W3", "PingFangSC-Regular", "HelveticaNeue"],
        fontSize: 16,
        textInsets: NSEdgeInsets(top: 18, left: 42, bottom: 16, right: 20),
        cornerRadius: 3,
        shadow: ShadowSpec(alpha: 0.26, blur: 16, offsetY: 6),
        extraTopMargin: 0,
        defaultWidth: 230,
        minWidth: 150,
        maxWidth: 480,
        paragraph: ParagraphSpec(lineHeightMultiple: 1.0, minimumLineHeight: 26),
        variants: [ColorVariant(name: "白", top: NSColor(calibratedWhite: 0.985, alpha: 1), ink: NSColor(calibratedRed: 0.18, green: 0.17, blue: 0.15, alpha: 1))],
        draw: Drawing.drawNotebook
    )

    // MARK: 2. 手写纸条 —— 米色撕边纸 + 顶部胶带 + 行楷
    public static let handwritten = StickerStyle(
        id: "handwritten",
        name: "手写纸条",
        fontNames: ["STXingkaiSC-Bold", "STXingkaiSC-Light", "HannotateSC-W5", "MarkerFelt-Wide"],
        fontSize: 21,
        textInsets: NSEdgeInsets(top: 40, left: 26, bottom: 24, right: 26),
        cornerRadius: 0,
        shadow: ShadowSpec(alpha: 0.20, blur: 14, offsetY: 5),
        extraTopMargin: 18,
        defaultWidth: 240,
        minWidth: 160,
        maxWidth: 520,
        paragraph: ParagraphSpec(lineHeightMultiple: 1.35),
        variants: [ColorVariant(name: "米", top: NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.88, alpha: 1), ink: NSColor(calibratedRed: 0.26, green: 0.22, blue: 0.17, alpha: 1))],
        draw: Drawing.drawHandwritten
    )

    // MARK: 3. 彩色便利贴 —— 经典黄 + 顶部胶条 + 右下折角，4 色变体
    public static let sticky = StickerStyle(
        id: "sticky",
        name: "彩色便利贴",
        fontNames: ["HannotateSC-W5", "MarkerFelt-Wide", "PingFangSC-Regular"],
        fontSize: 19,
        textInsets: NSEdgeInsets(top: 22, left: 22, bottom: 24, right: 22),
        cornerRadius: 2,
        shadow: ShadowSpec(alpha: 0.24, blur: 12, offsetY: 4),
        extraTopMargin: 0,
        defaultWidth: 220,
        minWidth: 150,
        maxWidth: 480,
        paragraph: ParagraphSpec(lineHeightMultiple: 1.4),
        variants: [
            ColorVariant(
                name: "柠檬黄",
                top: NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.45, alpha: 1),
                bottom: NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.25, alpha: 1),
                ink: NSColor(calibratedRed: 0.29, green: 0.23, blue: 0.07, alpha: 1)
            ),
            ColorVariant(
                name: "蜜桃粉",
                top: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.83, alpha: 1),
                bottom: NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.75, alpha: 1),
                ink: NSColor(calibratedRed: 0.42, green: 0.14, blue: 0.22, alpha: 1)
            ),
            ColorVariant(
                name: "薄荷绿",
                top: NSColor(calibratedRed: 0.71, green: 0.91, blue: 0.80, alpha: 1),
                bottom: NSColor(calibratedRed: 0.59, green: 0.87, blue: 0.72, alpha: 1),
                ink: NSColor(calibratedRed: 0.12, green: 0.27, blue: 0.20, alpha: 1)
            ),
            ColorVariant(
                name: "海盐蓝",
                top: NSColor(calibratedRed: 0.71, green: 0.85, blue: 0.96, alpha: 1),
                bottom: NSColor(calibratedRed: 0.58, green: 0.78, blue: 0.93, alpha: 1),
                ink: NSColor(calibratedRed: 0.08, green: 0.23, blue: 0.36, alpha: 1)
            ),
        ],
        draw: Drawing.drawSticky
    )

    // MARK: 4. 极简卡片 —— 纯白、发丝边、大留白、一点暖色点缀
    public static let minimal = StickerStyle(
        id: "minimal",
        name: "极简卡片",
        fontNames: ["PingFangSC-Medium", "HelveticaNeue-Medium"],
        fontSize: 17,
        textInsets: NSEdgeInsets(top: 32, left: 26, bottom: 26, right: 26),
        cornerRadius: 12,
        shadow: ShadowSpec(alpha: 0.18, blur: 22, offsetY: 10),
        extraTopMargin: 0,
        defaultWidth: 240,
        minWidth: 170,
        maxWidth: 520,
        paragraph: ParagraphSpec(lineHeightMultiple: 1.5, kern: 0.2),
        variants: [ColorVariant(name: "白", top: .white, ink: NSColor(calibratedWhite: 0.11, alpha: 1))],
        draw: Drawing.drawMinimal
    )

    // MARK: 5. 复古纸张 —— 泛黄做旧、污渍、双线框、魏碑
    public static let vintage = StickerStyle(
        id: "vintage",
        name: "复古纸张",
        fontNames: ["WeibeiSC-Bold", "Baskerville", "PingFangSC-Semibold"],
        fontSize: 19,
        textInsets: NSEdgeInsets(top: 32, left: 36, bottom: 30, right: 34),
        cornerRadius: 2,
        shadow: ShadowSpec(alpha: 0.30, blur: 14, offsetY: 5),
        extraTopMargin: 0,
        defaultWidth: 250,
        minWidth: 170,
        maxWidth: 520,
        paragraph: ParagraphSpec(lineHeightMultiple: 1.4),
        variants: [ColorVariant(
            name: "陈纸",
            top: NSColor(calibratedRed: 0.96, green: 0.91, blue: 0.80, alpha: 1),
            bottom: NSColor(calibratedRed: 0.91, green: 0.84, blue: 0.69, alpha: 1),
            ink: NSColor(calibratedRed: 0.29, green: 0.20, blue: 0.09, alpha: 1)
        )],
        draw: Drawing.drawVintage
    )

    // MARK: 6. 黑板 —— 墨绿板面、木框、粉笔描边、粉笔灰
    public static let blackboard = StickerStyle(
        id: "blackboard",
        name: "黑板",
        fontNames: ["YuppySC-Regular", "ChalkboardSE-Regular", "HannotateSC-W5"],
        fontSize: 19,
        textInsets: NSEdgeInsets(top: 30, left: 34, bottom: 28, right: 32),
        cornerRadius: 10,
        shadow: ShadowSpec(alpha: 0.34, blur: 16, offsetY: 6),
        extraTopMargin: 0,
        defaultWidth: 250,
        minWidth: 180,
        maxWidth: 520,
        paragraph: ParagraphSpec(lineHeightMultiple: 1.45),
        variants: [ColorVariant(
            name: "墨绿",
            top: NSColor(calibratedRed: 0.16, green: 0.25, blue: 0.21, alpha: 1),
            bottom: NSColor(calibratedRed: 0.13, green: 0.21, blue: 0.18, alpha: 1),
            ink: NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.89, alpha: 1)
        )],
        draw: Drawing.drawBlackboard
    )

    // MARK: 7. 可爱插画 —— 粉底、白描边、虚线框、星星与爱心
    public static let cute = StickerStyle(
        id: "cute",
        name: "可爱插画",
        fontNames: ["ArialRoundedMTBold", "HannotateSC-W7", "PingFangSC-Semibold"],
        fontSize: 18,
        textInsets: NSEdgeInsets(top: 30, left: 26, bottom: 28, right: 26),
        cornerRadius: 18,
        shadow: ShadowSpec(color: NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.35, alpha: 1), alpha: 0.22, blur: 14, offsetY: 6),
        extraTopMargin: 0,
        defaultWidth: 230,
        minWidth: 160,
        maxWidth: 480,
        paragraph: ParagraphSpec(lineHeightMultiple: 1.4),
        variants: [ColorVariant(
            name: "樱花粉",
            top: NSColor(calibratedRed: 1.0, green: 0.89, blue: 0.93, alpha: 1),
            bottom: NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.91, alpha: 1),
            ink: NSColor(calibratedRed: 0.76, green: 0.25, blue: 0.48, alpha: 1)
        )],
        draw: Drawing.drawCute
    )

    // MARK: 8. 极简现代 —— 深色玻璃、等宽字体、薄荷强调线
    public static let mono = StickerStyle(
        id: "mono",
        name: "极简现代",
        fontNames: ["Menlo-Regular", "CourierNewPSMT", "Menlo"],
        fontSize: 15,
        textInsets: NSEdgeInsets(top: 30, left: 24, bottom: 26, right: 24),
        cornerRadius: 10,
        shadow: ShadowSpec(alpha: 0.38, blur: 20, offsetY: 8),
        extraTopMargin: 0,
        defaultWidth: 260,
        minWidth: 180,
        maxWidth: 560,
        paragraph: ParagraphSpec(lineHeightMultiple: 1.55),
        variants: [ColorVariant(
            name: "碳黑",
            top: NSColor(calibratedRed: 0.115, green: 0.122, blue: 0.142, alpha: 1),
            bottom: NSColor(calibratedRed: 0.095, green: 0.10, blue: 0.12, alpha: 1),
            ink: NSColor(calibratedRed: 0.91, green: 0.92, blue: 0.93, alpha: 1)
        )],
        draw: Drawing.drawMono
    )
}
