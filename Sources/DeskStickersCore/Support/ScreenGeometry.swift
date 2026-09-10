import AppKit

/// 屏幕几何工具：级联摆放、恢复时的可见区域约束。
public enum ScreenGeometry {

    /// 新贴纸的默认摆放：主屏可见区域中央附近，按已有贴纸数量级联错开，避免完全重叠。
    public static func cascadeOrigin(existingFrames: [CGRect], size: CGSize) -> CGPoint {
        let visible = primaryVisibleFrame()
        let baseX = visible.midX - size.width / 2
        let baseY = visible.midY - size.height / 2 + 40

        for step in 0..<48 {
            let column = step % 8
            let row = step / 8
            let x = baseX + CGFloat(column) * 30
            let y = baseY - CGFloat(row) * 42 - CGFloat(column) * 16
            let candidate = CGRect(origin: CGPoint(x: x, y: y), size: size)
            let clamped = clampFrame(candidate, into: visible)
            if !existingFrames.contains(where: { $0.intersects(clamped) }) {
                return clamped.origin
            }
        }
        // 兜底：回到基准位。
        return clampFrame(CGRect(origin: CGPoint(x: baseX, y: baseY), size: size), into: visible).origin
    }

    /// 恢复时确保纸面至少有 60% 落在某块屏幕的可见区域内，否则搬回主屏。
    ///
    /// 用可见区域（不含菜单栏/Dock）：贴纸保持完整可见，
    /// 最高位置 = 菜单栏正下方。
    public static func rescueFrame(_ frame: CGRect) -> CGRect {
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            let intersection = frame.intersection(visible)
            guard !intersection.isNull else { continue }
            let visibleArea = max(visible.width * visible.height, 1)
            if intersection.width * intersection.height >= 0.6 * min(frame.width * frame.height, visibleArea) {
                return clampFrame(frame, into: visible)
            }
        }
        let visible = primaryVisibleFrame()
        let size = CGSize(width: min(frame.width, visible.width * 0.8), height: min(frame.height, visible.height * 0.8))
        return clampFrame(CGRect(origin: CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2), size: size), into: visible)
    }

    /// 将矩形完整约束进给定区域（优先保住左上角语义：贴合时优先保留 top-left）。
    public static func clampFrame(_ frame: CGRect, into bounds: CGRect) -> CGRect {
        var result = frame
        if result.width > bounds.width { result.size.width = bounds.width }
        if result.height > bounds.height { result.size.height = bounds.height }
        // 水平：尽量保留原位置，越界则贴边。
        result.origin.x = min(max(result.origin.x, bounds.minX), bounds.maxX - result.width)
        // 垂直：尽量保留顶边。
        let top = result.maxY
        if top > bounds.maxY { result.origin.y = bounds.maxY - result.height }
        if result.origin.y < bounds.minY { result.origin.y = bounds.minY }
        return result
    }

    public static func primaryVisibleFrame() -> CGRect {
        if let main = NSScreen.main { return main.visibleFrame }
        if let first = NSScreen.screens.first { return first.visibleFrame }
        return CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// 可见顶边界：纸面顶边不越过任何水平相交屏幕的可见区顶（菜单栏/刘海区域）。
    ///
    /// 贴纸保持完整可见（最高停在菜单栏正下方），不钻到菜单栏后面。
    /// 外接屏无菜单栏（visibleFrame = frame），可到外接屏顶；
    /// 横跨多屏时取最严格的可见区顶。无相交屏幕时原样返回。
    public static func clampBelowMenuBar(_ frame: CGRect) -> CGRect {
        var topLimit: CGFloat?
        for screen in NSScreen.screens {
            guard frame.minX < screen.frame.maxX, frame.maxX > screen.frame.minX else { continue }
            let limit = screen.visibleFrame.maxY
            topLimit = topLimit.map { min($0, limit) } ?? limit
        }
        guard let limit = topLimit, frame.maxY > limit else { return frame }
        var result = frame
        result.origin.y = limit - result.height
        return result
    }

    /// AppKit 全局坐标（原点左下）→ CG 顶左坐标，用于与 CGWindowList 对账。
    public static func cgTopLeftRect(_ frame: CGRect) -> CGRect {
        guard let screenFrame = NSScreen.screens.first?.frame else { return frame }
        let primaryHeight = screenFrame.height
        return CGRect(
            x: frame.minX,
            y: primaryHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
