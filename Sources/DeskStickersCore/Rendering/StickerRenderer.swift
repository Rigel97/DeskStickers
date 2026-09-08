import AppKit

/// 风格绘制实现。所有坐标均在“纸面局部坐标系”（翻转：原点在纸面左上角，y 向下）。
public enum Drawing {

    // MARK: - 1. 便签纸

    static func drawNotebook(_ ctx: StickerDrawContext) {
        let r = ctx.paper
        let variant = ctx.variant

        // 纸面（带阴影）
        setShadow(ctx)
        fillRounded(r, radius: 3, color: variant.top)
        clearShadow()

        // 细边框
        strokeRounded(r.insetBy(dx: 0.5, dy: 0.5), radius: 2.5,
                      color: NSColor(calibratedRed: 0.89, green: 0.87, blue: 0.82, alpha: 1), width: 1)

        // 淡蓝横线（与 minimumLineHeight=26 的行距对齐）
        let lineColor = NSColor(calibratedRed: 0.76, green: 0.84, blue: 0.92, alpha: 1)
        var y = ctx.textInsets.top + 24.5
        while y < r.height - 9 {
            strokeLine(from: CGPoint(x: 36, y: y), to: CGPoint(x: r.width - 13, y: y), color: lineColor, width: 1)
            y += 26
        }

        // 左侧红色边线
        strokeLine(from: CGPoint(x: 30, y: 13), to: CGPoint(x: 30, y: r.height - 9),
                   color: NSColor(calibratedRed: 0.92, green: 0.65, blue: 0.65, alpha: 1), width: 1.2)
    }

    // MARK: - 2. 手写纸条

    static func drawHandwritten(_ ctx: StickerDrawContext) {
        let r = ctx.paper
        let variant = ctx.variant

        // 撕边纸面（阴影跟随撕边轮廓）
        let path = tornPaperPath(r, seed: 0x5EED)
        setShadow(ctx)
        fillPathGradient(path, rect: r, start: .top, end: .bottom, top: variant.top,
                         bottom: variant.top.blended(with: NSColor(calibratedRed: 0.72, green: 0.62, blue: 0.44, alpha: 1), amount: 0.12))
        clearShadow()

        // 顶部胶带（压在纸面上缘，略微旋转）
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.translateBy(x: r.midX, y: 0)
        cg.rotate(by: -3.5 * .pi / 180)
        let tape = CGRect(x: -56, y: -14, width: 112, height: 30)
        let tapeColor = NSColor(calibratedRed: 0.90, green: 0.83, blue: 0.64, alpha: 0.94)
        fillRect(tape, color: tapeColor)
        // 胶带两端压痕
        fillRect(CGRect(x: tape.minX, y: tape.minY, width: 5, height: tape.height),
                 color: NSColor(calibratedWhite: 0.4, alpha: 0.16))
        fillRect(CGRect(x: tape.maxX - 5, y: tape.minY, width: 5, height: tape.height),
                 color: NSColor(calibratedWhite: 0.4, alpha: 0.16))
        // 胶带上的一丝高光
        strokeLine(from: CGPoint(x: tape.minX + 8, y: tape.minY + 6), to: CGPoint(x: tape.maxX - 8, y: tape.minY + 6),
                   color: NSColor(calibratedWhite: 1, alpha: 0.28), width: 1)
        cg.restoreGState()
    }

    // MARK: - 3. 彩色便利贴

    static func drawSticky(_ ctx: StickerDrawContext) {
        let r = ctx.paper
        let variant = ctx.variant

        setShadow(ctx)
        fillRoundedGradient(r, radius: 2, top: variant.top, bottom: variant.bottom)
        clearShadow()

        // 顶部胶条（微微提亮）
        fillRounded(CGRect(x: 1, y: 0, width: r.width - 2, height: 14), radius: 1.5,
                    color: NSColor(calibratedWhite: 1, alpha: 0.22))

        // 右下折角
        let f: CGFloat = 22
        let p1 = CGPoint(x: r.width - f, y: r.height)      // 折痕下端
        let p2 = CGPoint(x: r.width, y: r.height - f)      // 折痕右端
        // 角落阴影（被折起的角下方）
        let corner = NSBezierPath()
        corner.move(to: p1)
        corner.line(to: p2)
        corner.line(to: CGPoint(x: r.width, y: r.height))
        corner.close()
        fillPath(corner, color: NSColor(calibratedWhite: 0, alpha: 0.13))
        // 折起的纸背（略浅）
        let flap = NSBezierPath()
        flap.move(to: p1)
        flap.line(to: p2)
        flap.line(to: CGPoint(x: r.width - f, y: r.height - f))
        flap.close()
        fillPath(flap, color: NSColor(calibratedWhite: 1, alpha: 0.38))
        // 折痕线
        strokeLine(from: p1, to: p2, color: NSColor(calibratedWhite: 0, alpha: 0.10), width: 1)
    }

    // MARK: - 4. 极简卡片

    static func drawMinimal(_ ctx: StickerDrawContext) {
        let r = ctx.paper
        let variant = ctx.variant

        setShadow(ctx)
        fillRounded(r, radius: 12, color: variant.top)
        clearShadow()

        strokeRounded(r.insetBy(dx: 0.5, dy: 0.5), radius: 11.5,
                      color: NSColor(calibratedWhite: 0.92, alpha: 1), width: 1)

        // 顶部一点暖色点缀
        fillRounded(CGRect(x: r.midX - 9, y: 15, width: 18, height: 3), radius: 1.5,
                    color: NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.35, alpha: 1))
    }

    // MARK: - 5. 复古纸张

    static func drawVintage(_ ctx: StickerDrawContext) {
        let r = ctx.paper
        let variant = ctx.variant
        let brown = NSColor(calibratedRed: 0.42, green: 0.31, blue: 0.14, alpha: 1)

        setShadow(ctx)
        fillRoundedGradient(r, radius: 2, top: variant.top,
                            bottom: variant.bottom,
                            start: .topLeft, end: .bottomRight)
        clearShadow()

        // 做旧：三处晕染
        var rng = SeededRandom(seed: 0xC0FFEE)
        for _ in 0..<3 {
            let cx = r.width * CGFloat(rng.next(in: 0.15...0.85))
            let cy = r.height * CGFloat(rng.next(in: 0.15...0.85))
            let radius = CGFloat(rng.next(in: 26...56))
            drawRadial(at: CGPoint(x: cx, y: cy), radius: radius,
                      color: NSColor(calibratedRed: 0.66, green: 0.50, blue: 0.26, alpha: 0.13))
        }

        // 边缘陈旧感（两圈渐弱的描边）
        strokeRounded(r.insetBy(dx: 3, dy: 3), radius: 1, color: brown.withAlphaComponent(0.10), width: 5)
        strokeRounded(r.insetBy(dx: 1.5, dy: 1.5), radius: 1.5, color: brown.withAlphaComponent(0.14), width: 2)

        // 双线画框
        strokeRounded(r.insetBy(dx: 10.5, dy: 10.5), radius: 1, color: brown.withAlphaComponent(0.85), width: 1.5)
        strokeRounded(r.insetBy(dx: 15, dy: 15), radius: 1, color: brown.withAlphaComponent(0.60), width: 0.75)

        // 内框四角菱形饰
        let inner = r.insetBy(dx: 15, dy: 15)
        for corner in [CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY),
                       CGPoint(x: inner.minX, y: inner.maxY), CGPoint(x: inner.maxX, y: inner.maxY)] {
            fillDiamond(at: corner, size: 3.2, color: brown.withAlphaComponent(0.85))
        }
    }

    // MARK: - 6. 黑板

    static func drawBlackboard(_ ctx: StickerDrawContext) {
        let r = ctx.paper
        let variant = ctx.variant

        // 木框
        setShadow(ctx)
        fillRounded(r, radius: 10, color: NSColor(calibratedRed: 0.66, green: 0.51, blue: 0.35, alpha: 1))
        clearShadow()
        strokeRounded(r.insetBy(dx: 0.75, dy: 0.75), radius: 9.25,
                      color: NSColor(calibratedRed: 0.49, green: 0.37, blue: 0.26, alpha: 1), width: 1.5)
        // 木框上缘高光
        strokeRounded(r.insetBy(dx: 2, dy: 2), radius: 8,
                      color: NSColor(calibratedWhite: 1, alpha: 0.18), width: 1)

        // 板面
        let board = r.insetBy(dx: 7, dy: 7)
        fillRoundedGradient(board, radius: 5, top: variant.top, bottom: variant.bottom)

        // 粉笔灰（确定性随机）
        var rng = SeededRandom(seed: 0x51A7E)
        for _ in 0..<16 {
            let x = CGFloat(rng.next(in: 8...max(9, board.width - 8)))
            let y = CGFloat(rng.next(in: 8...max(9, board.height - 8)))
            let s = CGFloat(rng.next(in: 0.6...1.4))
            fillRect(CGRect(x: board.minX + x, y: board.minY + y, width: s, height: s),
                     color: NSColor(calibratedWhite: 1, alpha: CGFloat(rng.next(in: 0.04...0.09))))
        }
        // 左下粉笔抹痕
        drawRadial(at: CGPoint(x: board.minX + 30, y: board.maxY - 16), radius: 34,
                   color: NSColor(calibratedWhite: 1, alpha: 0.05))

        // 粉笔描边框
        strokeRounded(board.insetBy(dx: 10, dy: 10), radius: 4,
                      color: NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.89, alpha: 0.72), width: 1.5)
    }

    // MARK: - 7. 可爱插画

    static func drawCute(_ ctx: StickerDrawContext) {
        let r = ctx.paper
        let variant = ctx.variant

        setShadow(ctx)
        fillRoundedGradient(r, radius: 18, top: variant.top, bottom: variant.bottom)
        clearShadow()

        // 白色粗描边
        strokeRounded(r.insetBy(dx: 1.5, dy: 1.5), radius: 16.5,
                      color: NSColor(calibratedWhite: 1, alpha: 1), width: 3)
        // 内侧虚线
        let dashed = NSBezierPath(roundedRect: r.insetBy(dx: 9, dy: 9), xRadius: 12, yRadius: 12)
        dashed.setLineDash([4, 4], count: 2, phase: 0)
        strokePath(dashed, color: NSColor(calibratedRed: 1.0, green: 0.61, blue: 0.77, alpha: 1), width: 1.5)

        // 星星与爱心装饰
        let accent = NSColor(calibratedRed: 1.0, green: 0.50, blue: 0.70, alpha: 1)
        fillStar4(at: CGPoint(x: 17, y: 16), size: 7, color: accent)
        fillStar4(at: CGPoint(x: r.width - 17, y: r.height - 16), size: 6, color: accent)
        fillHeart(at: CGPoint(x: r.width - 16, y: 16), size: 7.5,
                  color: NSColor(calibratedRed: 1.0, green: 0.71, blue: 0.81, alpha: 1))
        fillCircle(at: CGPoint(x: 16, y: r.height - 15), radius: 2.5,
                   color: NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.86, alpha: 1))
    }

    // MARK: - 8. 极简现代

    static func drawMono(_ ctx: StickerDrawContext) {
        let r = ctx.paper
        let variant = ctx.variant

        setShadow(ctx)
        fillRoundedGradient(r, radius: 10, top: variant.top, bottom: variant.bottom)
        clearShadow()

        strokeRounded(r.insetBy(dx: 0.5, dy: 0.5), radius: 9.5,
                      color: NSColor(calibratedRed: 0.20, green: 0.215, blue: 0.243, alpha: 1), width: 1)

        // 薄荷色强调线
        fillRounded(CGRect(x: 24, y: 18, width: 18, height: 3), radius: 1.5,
                    color: NSColor(calibratedRed: 0.365, green: 0.839, blue: 0.659, alpha: 1))
    }
}

// MARK: - 绘制辅助（翻转坐标系友好）

enum GradientDirection {
    case top, bottom, topLeft, bottomRight
}

func setShadow(_ ctx: StickerDrawContext) {
    guard let context = NSGraphicsContext.current else { return }
    let spec = ctx.shadow
    let shadow = NSShadow()
    // 画布是翻转坐标系：视觉向下的阴影需要取负 y。
    shadow.shadowOffset = NSSize(width: 0, height: -spec.offsetY)
    shadow.shadowBlurRadius = spec.blur
    shadow.shadowColor = spec.color.withAlphaComponent(spec.alpha)
    context.saveGraphicsState()
    shadow.set()
}

func clearShadow() {
    NSGraphicsContext.current?.restoreGraphicsState()
}

func fillRounded(_ rect: CGRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func strokeRounded(_ rect: CGRect, radius: CGFloat, color: NSColor, width: CGFloat) {
    color.setStroke()
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.lineWidth = width
    path.stroke()
}

func fillRect(_ rect: CGRect, color: NSColor) {
    color.setFill()
    rect.fill()
}

func strokeLine(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat) {
    color.setStroke()
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineWidth = width
    path.stroke()
}

func fillPath(_ path: NSBezierPath, color: NSColor) {
    color.setFill()
    path.fill()
}

func strokePath(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

func fillCircle(at center: CGPoint, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
}

func fillDiamond(at center: CGPoint, size: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: center.x, y: center.y - size))
    path.line(to: CGPoint(x: center.x + size, y: center.y))
    path.line(to: CGPoint(x: center.x, y: center.y + size))
    path.line(to: CGPoint(x: center.x - size, y: center.y))
    path.close()
    fillPath(path, color: color)
}

func fillStar4(at center: CGPoint, size: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    let inner = size * 0.32
    path.move(to: CGPoint(x: center.x, y: center.y - size))
    path.line(to: CGPoint(x: center.x + inner, y: center.y - inner))
    path.line(to: CGPoint(x: center.x + size, y: center.y))
    path.line(to: CGPoint(x: center.x + inner, y: center.y + inner))
    path.line(to: CGPoint(x: center.x, y: center.y + size))
    path.line(to: CGPoint(x: center.x - inner, y: center.y + inner))
    path.line(to: CGPoint(x: center.x - size, y: center.y))
    path.line(to: CGPoint(x: center.x - inner, y: center.y - inner))
    path.close()
    fillPath(path, color: color)
}

func fillHeart(at center: CGPoint, size: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    let s = size
    path.move(to: CGPoint(x: center.x, y: center.y + s * 0.9))
    path.curve(to: CGPoint(x: center.x - s, y: center.y - s * 0.25),
               controlPoint1: CGPoint(x: center.x - s * 0.9, y: center.y + s * 0.35),
               controlPoint2: CGPoint(x: center.x - s, y: center.y - s * 0.05))
    path.curve(to: CGPoint(x: center.x, y: center.y - s * 0.75),
               controlPoint1: CGPoint(x: center.x - s, y: center.y - s * 0.75),
               controlPoint2: CGPoint(x: center.x - s * 0.35, y: center.y - s * 0.8))
    path.curve(to: CGPoint(x: center.x + s, y: center.y - s * 0.25),
               controlPoint1: CGPoint(x: center.x + s * 0.35, y: center.y - s * 0.8),
               controlPoint2: CGPoint(x: center.x + s, y: center.y - s * 0.75))
    path.curve(to: CGPoint(x: center.x, y: center.y + s * 0.9),
               controlPoint1: CGPoint(x: center.x + s, y: center.y - s * 0.05),
               controlPoint2: CGPoint(x: center.x + s * 0.9, y: center.y + s * 0.35))
    path.close()
    fillPath(path, color: color)
}

/// 线性渐变填充（起点/终点按视觉方向描述，适配翻转坐标系）。
func fillRoundedGradient(_ rect: CGRect, radius: CGFloat, top: NSColor, bottom: NSColor,
                         start: GradientDirection = .top, end: GradientDirection = .bottom) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fillPathGradient(path, rect: rect, start: start, end: end, top: top, bottom: bottom)
}

func fillPathGradient(_ path: NSBezierPath, rect: CGRect, start: GradientDirection,
                      end: GradientDirection, top: NSColor, bottom: NSColor) {
    guard let cg = NSGraphicsContext.current?.cgContext else { return }
    cg.saveGState()
    path.addClip()
    let startP: CGPoint
    let endP: CGPoint
    switch start {
    case .top: startP = CGPoint(x: rect.midX, y: rect.minY)
    case .bottom: startP = CGPoint(x: rect.midX, y: rect.maxY)
    case .topLeft: startP = CGPoint(x: rect.minX, y: rect.minY)
    case .bottomRight: startP = CGPoint(x: rect.maxX, y: rect.maxY)
    }
    switch end {
    case .top: endP = CGPoint(x: rect.midX, y: rect.minY)
    case .bottom: endP = CGPoint(x: rect.midX, y: rect.maxY)
    case .topLeft: endP = CGPoint(x: rect.minX, y: rect.minY)
    case .bottomRight: endP = CGPoint(x: rect.maxX, y: rect.maxY)
    }
    let colors = [top.cgColor, bottom.cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else {
        cg.restoreGState()
        return
    }
    cg.drawLinearGradient(gradient, start: startP, end: endP, options: [])
    cg.restoreGState()
}

func drawRadial(at center: CGPoint, radius: CGFloat, color: NSColor) {
    guard let cg = NSGraphicsContext.current?.cgContext else { return }
    let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
    cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// 撕边纸面路径：上缘平直，左右与下缘呈锯齿状抖动（确定性随机）。
func tornPaperPath(_ rect: CGRect, seed: UInt32) -> NSBezierPath {
    var rng = SeededRandom(seed: seed)
    let path = NSBezierPath()
    let step: CGFloat = 22
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    // 顶边：平直
    path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
    // 右边：向下抖动
    var y = rect.minY + step
    while y < rect.maxY - step * 0.5 {
        path.line(to: CGPoint(x: rect.maxX + CGFloat(rng.next(in: -4.0...3.0)), y: y))
        y += step
    }
    // 底边：向左抖动
    var x = rect.maxX
    while x > rect.minX + step * 0.5 {
        path.line(to: CGPoint(x: x, y: rect.maxY + CGFloat(rng.next(in: -4.0...4.0))))
        x -= step
    }
    // 左边：向上抖动
    y = rect.maxY
    while y > rect.minY + step * 0.5 {
        path.line(to: CGPoint(x: rect.minX + CGFloat(rng.next(in: -4.0...3.0)), y: y))
        y -= step
    }
    path.close()
    return path
}

/// 确定性伪随机（LCG），保证装饰每次绘制完全一致。
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt32) { state = UInt64(seed) &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func nextRaw() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(nextRaw() % 10_000_000) / 10_000_000.0
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

extension NSColor {
    func blended(with other: NSColor, amount: CGFloat) -> NSColor {
        self.blended(withFraction: amount, of: other) ?? self
    }
}
