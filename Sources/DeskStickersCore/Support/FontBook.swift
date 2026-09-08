import AppKit

/// 字体解析：按 PostScript 名 → 家族名的顺序尝试，全部失败时回退系统字体。
/// macOS 的中文展示字体（行楷/魏碑/手札体等）在部分机器上是可选下载，
/// 因此每个风格都准备了完整的回退链。
public enum FontBook {

    public static func font(postScriptNames: [String], size: CGFloat) -> NSFont {
        for name in postScriptNames {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        // 家族名兜底
        for name in postScriptNames {
            let descriptor = NSFontDescriptor(fontAttributes: [.family: name])
            if let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
        }
        return NSFont.systemFont(ofSize: size)
    }

    /// 供单元测试断言：主字体是否可用。
    public static func isResolvable(_ postScriptNames: [String]) -> Bool {
        for name in postScriptNames {
            if NSFont(name: name, size: 16) != nil { return true }
            let descriptor = NSFontDescriptor(fontAttributes: [.family: name])
            if NSFont(descriptor: descriptor, size: 16) != nil { return true }
        }
        return false
    }
}
