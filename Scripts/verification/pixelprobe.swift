import AppKit

// PNG 像素采样工具
// 用法:
//   pixelprobe <png> [--avg x y w h | x y ...]      屏幕逻辑坐标（左上原点），按主屏缩放换算
//   pixelprobe <png> raw [--avg x y w h | x y ...]  图像像素坐标（左上原点，直接采样）
//   pixelprobe <png> rawboth x y                    顶左/底左双采样（方向校准用）
func colorAt(_ rep: NSBitmapImageRep, _ px: Int, _ py: Int) -> (Int, Int, Int)? {
    guard px >= 0, py >= 0, px < rep.pixelsWide, py < rep.pixelsHigh,
          let c = rep.colorAt(x: px, y: py) else { return nil }
    return (Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: pixelprobe <png> [raw] [--avg x y w h | x y ...]")
    exit(1)
}
let path = args[1]
guard let img = NSImage(contentsOfFile: path), let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    print("ERR: cannot load image \(path)")
    exit(2)
}

var raw = false
var cursor = 2
if args[cursor] == "raw" { raw = true; cursor += 1 }

func convert(_ x: CGFloat, _ y: CGFloat) -> (Int, Int) {
    if raw {
        return (Int(round(x)), Int(round(y)))
    }
    let screen = NSScreen.main!
    let scale = CGFloat(rep.pixelsWide) / screen.frame.size.width
    return (Int(round(x * scale)), Int(round((screen.frame.size.height - y) * scale)))
}

func probePoint(_ x: CGFloat, _ y: CGFloat) {
    let (px, py) = convert(x, y)
    if let (r, g, b) = colorAt(rep, px, py) {
        print("POINT(\(Int(x)),\(Int(y))) = rgb(\(r),\(g),\(b))")
    } else {
        print("POINT(\(Int(x)),\(Int(y))) = OUT_OF_RANGE (image \(rep.pixelsWide)x\(rep.pixelsHigh))")
    }
}

func probeAvg(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    var rs = 0.0, gs = 0.0, bs = 0.0, n = 0.0
    var samples: [(Int, Int, Int)] = []
    let stepX = max(1, w / 8), stepY = max(1, h / 8)
    var yy = y + 1
    while yy < y + h - 1 {
        var xx = x + 1
        while xx < x + w - 1 {
            let (px, py) = convert(xx, yy)
            if let (r, g, b) = colorAt(rep, px, py) {
                rs += Double(r); gs += Double(g); bs += Double(b); n += 1
                samples.append((r, g, b))
            }
            xx += stepX
        }
        yy += stepY
    }
    guard n > 0 else { print("AVG(\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))) = OUT_OF_RANGE"); return }
    let r = Int(rs / n), g = Int(gs / n), b = Int(bs / n)
    let counts = Dictionary(grouping: samples, by: { "\($0.0),\($0.1),\($0.2)" }).mapValues { $0.count }
    let domKey = counts.max { $0.value < $1.value }!.key
    let domParts = domKey.split(separator: ",").map { Int($0) ?? 0 }
    print("AVG(\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))) = rgb(\(r),\(g),\(b)) dominant=rgb(\(domParts[0]),\(domParts[1]),\(domParts[2])) n=\(Int(n))")
}

guard cursor < args.count else { print("ERR: no probe args"); exit(1) }

if args[cursor] == "rawboth" {
    guard args.count >= cursor + 3,
          let x = Double(args[cursor + 1]), let y = Double(args[cursor + 2]) else { exit(1) }
    let px = Int(x)
    if let (r, g, b) = colorAt(rep, px, Int(y)) {
        print("TOPLEFT(\(px),\(Int(y))) = rgb(\(r),\(g),\(b))")
    }
    if let (r, g, b) = colorAt(rep, px, rep.pixelsHigh - 1 - Int(y)) {
        print("BOTTOMLEFT(\(px),\(Int(y))) = rgb(\(r),\(g),\(b))")
    }
    exit(0)
}

if args[cursor] == "--avg" {
    guard args.count >= cursor + 5,
          let x = Double(args[cursor + 1]), let y = Double(args[cursor + 2]),
          let w = Double(args[cursor + 3]), let h = Double(args[cursor + 4]) else {
        print("ERR: bad --avg args"); exit(1)
    }
    probeAvg(CGFloat(x), CGFloat(y), CGFloat(w), CGFloat(h))
} else {
    var i = cursor
    while i + 1 <= args.count - 1 {
        guard let x = Double(args[i]), let y = Double(args[i + 1]) else { break }
        probePoint(CGFloat(x), CGFloat(y))
        i += 2
    }
}
