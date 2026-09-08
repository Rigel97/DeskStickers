import AppKit
import CoreGraphics

// 列出屏幕上的窗口（CGWindowList 元数据无需屏幕录制权限）
let opts: CGWindowListOption = [.optionOnScreenOnly]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    print("ERR: cannot list windows")
    exit(1)
}
print("total onscreen windows: \(list.count)")
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    let layer = w[kCGWindowLayer as String] as? Int ?? -999
    let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let name = w[kCGWindowName as String] as? String ?? ""
    let x = bounds["X"] as? Int ?? 0, y = bounds["Y"] as? Int ?? 0
    let w2 = bounds["Width"] as? Int ?? 0, h = bounds["Height"] as? Int ?? 0
    print("layer=\(layer) owner=\(owner) name='\(name)' frame=(\(x),\(y),\(w2)x\(h))")
}
