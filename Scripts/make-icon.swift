import AppKit

// 生成应用图标：以便利贴为原型的 1024px 主图。
// 输出路径由第一个参数指定，默认 /tmp/DeskStickers-icon-1024.png

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/DeskStickers-icon-1024.png"
let size = 1024

guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("无法创建位图上下文".utf8))
    exit(1)
}

let s = CGFloat(size)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// 背景：便利贴黄渐变的圆角方块（macOS 图标栅格近似圆角）
let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: s * 0.225, cornerHeight: s * 0.225, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: [color(1.0, 0.91, 0.45), color(1.0, 0.79, 0.24)] as CFArray,
                            locations: [0, 1])!
ctx.drawLinearGradient(bgGradient, start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: 0), options: [])
// 上缘高光
let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [color(1, 1, 1, 0.35), color(1, 1, 1, 0)] as CFArray,
                           locations: [0, 1])!
ctx.drawLinearGradient(highlight, start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: s * 0.7), options: [])
ctx.restoreGState()

// 白色纸面（轻微旋转）
ctx.saveGState()
ctx.translateBy(x: s / 2, y: s / 2)
ctx.rotate(by: -7 * .pi / 180)
ctx.translateBy(x: -s / 2, y: -s / 2)

let paperSize = CGSize(width: s * 0.62, height: s * 0.66)
let paperRect = CGRect(
    x: (s - paperSize.width) / 2,
    y: (s - paperSize.height) / 2,
    width: paperSize.width, height: paperSize.height
)
// 纸面阴影
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: color(0.15, 0.12, 0.02, 0.38))
let paperPath = CGPath(roundedRect: paperRect, cornerWidth: 26, cornerHeight: 26, transform: nil)
ctx.addPath(paperPath)
ctx.setFillColor(color(1.0, 0.99, 0.96))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// 三条“文字”条
let barInset = paperRect.width * 0.14
let barWidth = paperRect.width - barInset * 2
let barHeight: CGFloat = 30
let startY = paperRect.maxY - paperRect.height * 0.22
for (index, widthFactor) in [1.0, 0.86, 0.62].enumerated() {
    let barRect = CGRect(
        x: paperRect.minX + barInset,
        y: startY - CGFloat(index) * 72,
        width: barWidth * widthFactor,
        height: barHeight
    )
    let barPath = CGPath(roundedRect: barRect, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil)
    ctx.addPath(barPath)
    ctx.setFillColor(index == 0 ? color(1.0, 0.83, 0.30) : color(0.87, 0.83, 0.74))
    ctx.fillPath()
}

// 右下折角
let fold: CGFloat = 86
ctx.beginPath()
ctx.move(to: CGPoint(x: paperRect.maxX - fold, y: paperRect.minY))
ctx.addLine(to: CGPoint(x: paperRect.maxX, y: paperRect.minY + fold))
ctx.addLine(to: CGPoint(x: paperRect.maxX - fold, y: paperRect.minY + fold))
ctx.closePath()
ctx.setFillColor(color(0.93, 0.89, 0.80))
ctx.fillPath()
ctx.beginPath()
ctx.move(to: CGPoint(x: paperRect.maxX - fold, y: paperRect.minY))
ctx.addLine(to: CGPoint(x: paperRect.maxX - fold, y: paperRect.minY + fold))
ctx.addLine(to: CGPoint(x: paperRect.maxX, y: paperRect.minY + fold))
ctx.closePath()
ctx.setFillColor(color(0, 0, 0, 0.08))
ctx.fillPath()

ctx.restoreGState()

// 顶部胶带（水平，压在纸面上缘）
let tapeWidth = s * 0.34
let tapeRect = CGRect(x: (s - tapeWidth) / 2, y: s * 0.855, width: tapeWidth, height: s * 0.085)
ctx.saveGState()
ctx.translateBy(x: s / 2, y: s / 2)
ctx.rotate(by: 4 * .pi / 180)
ctx.translateBy(x: -s / 2, y: -s / 2)
ctx.setFillColor(color(0.92, 0.85, 0.66, 0.95))
ctx.fill(tapeRect)
ctx.setFillColor(color(0.45, 0.38, 0.22, 0.16))
ctx.fill(CGRect(x: tapeRect.minX, y: tapeRect.minY, width: 14, height: tapeRect.height))
ctx.fill(CGRect(x: tapeRect.maxX - 14, y: tapeRect.minY, width: 14, height: tapeRect.height))
ctx.restoreGState()

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("无法生成图像".utf8))
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("无法编码 PNG".utf8))
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: output))
print("图标已生成: \(output)")
