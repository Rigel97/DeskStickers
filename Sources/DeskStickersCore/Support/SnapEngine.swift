import AppKit

/// 拖动吸附：屏幕安全区、屏幕中线、其他贴纸边缘/中线对齐。
///
/// 输入输出均为 AppKit 全局坐标（原点左下）。纯函数集合，便于单测。
public enum SnapEngine {

    /// 一次吸附的结果：调整后的窗口原点 + 需要展示的参考线。
    public struct Result {
        public var origin: CGPoint
        public var guides: [Guide]
    }

    /// 对齐参考线（AppKit 全局坐标的水平/垂直线段）。
    public struct Guide {
        public enum Axis { case vertical, horizontal }
        public var axis: Axis
        /// 线的位置（vertical = x，horizontal = y）。
        public var position: CGFloat
        /// 参考线可视区间（仅在两贴纸重叠区间内画线，避免满屏长线）。
        public var range: ClosedRange<CGFloat>
    }

    /// 吸附阈值（pt）：小于该距离时触发吸附。
    public static let threshold: CGFloat = 7

    /// 计算吸附后的窗口原点。
    /// - Parameters:
    ///   - windowFrame: 当前拖动中的窗口 frame（AppKit 坐标）。
    ///   - movingID: 正在拖动的贴纸 id（排除自身）。
    ///   - otherStickers: 其他贴纸的纸面矩形。
    ///   - screens: 屏幕可见区域（不含菜单栏/Dock）。最高停靠位 = 可见区顶
    ///     （菜单栏正下方，贴纸完整可见；顶部边界由 ScreenGeometry.clampBelowMenuBar 负责）。
    ///   - dragDelta: 本帧拖动位移（窗口原点逐帧变化量）。屏幕边缘候选仅在本帧
    ///     朝向该边缘时吸附；正要离开停靠位时不回拉。默认 .zero = 双向（旧行为）。
    public static func snap(windowFrame: CGRect, movingID: UUID,
                            otherStickers: [(id: UUID, frame: CGRect)],
                            screens: [NSRect],
                            dragDelta: CGPoint = .zero) -> Result {
        var origin = windowFrame.origin
        var guides: [Guide] = []
        // 全局各吸附候选按距离竞争，最终各轴只取距离最小者。
        var bestX: (position: CGFloat, delta: CGFloat, guide: Guide?)?
        var bestY: (position: CGFloat, delta: CGFloat, guide: Guide?)?

        func considerX(_ position: CGFloat, delta: CGFloat, guide: Guide?) {
            guard abs(delta) <= threshold else { return }
            if bestX == nil || abs(delta) < abs(bestX!.delta) {
                bestX = (position, delta, guide)
            }
        }
        func considerY(_ position: CGFloat, delta: CGFloat, guide: Guide?) {
            guard abs(delta) <= threshold else { return }
            if bestY == nil || abs(delta) < abs(bestY!.delta) {
                bestY = (position, delta, guide)
            }
        }

        // 1) 其他贴纸：边缘对边缘、中线对中线
        for other in otherStickers where other.id != movingID {
            let f = other.frame
            // 垂直方向候选（x 轴）：左左 / 右右 / 左右 / 右左 / 中线
            considerX(f.minX, delta: f.minX - windowFrame.minX,
                      guide: verticalGuide(at: f.minX, between: windowFrame, and: f))
            considerX(f.maxX, delta: f.maxX - windowFrame.maxX,
                      guide: verticalGuide(at: f.maxX, between: windowFrame, and: f))
            considerX(f.minX, delta: f.minX - windowFrame.maxX,
                      guide: verticalGuide(at: f.minX, between: windowFrame, and: f))
            considerX(f.maxX, delta: f.maxX - windowFrame.minX,
                      guide: verticalGuide(at: f.maxX, between: windowFrame, and: f))
            considerX(f.midX, delta: f.midX - windowFrame.midX,
                      guide: verticalGuide(at: f.midX, between: windowFrame, and: f))
            // 水平方向候选（y 轴）
            considerY(f.minY, delta: f.minY - windowFrame.minY,
                      guide: horizontalGuide(at: f.minY, between: windowFrame, and: f))
            considerY(f.maxY, delta: f.maxY - windowFrame.maxY,
                      guide: horizontalGuide(at: f.maxY, between: windowFrame, and: f))
            considerY(f.minY, delta: f.minY - windowFrame.maxY,
                      guide: horizontalGuide(at: f.minY, between: windowFrame, and: f))
            considerY(f.maxY, delta: f.maxY - windowFrame.minY,
                      guide: horizontalGuide(at: f.maxY, between: windowFrame, and: f))
            considerY(f.midY, delta: f.midY - windowFrame.midY,
                      guide: horizontalGuide(at: f.midY, between: windowFrame, and: f))
        }

        // 2) 屏幕安全区：贴纸拖到屏幕边缘时吸附到可见区域边缘（贴边摆放）。
        //    方向感知：屏幕边缘是「停靠点」而非「墙」——仅当本帧拖动迎向该边缘时才吸附，
        //    正在离开时不回拉。否则阈值带（7pt）内慢速拖动每帧都被拉回，永远出不来。
        //    顶部边界（菜单栏下缘）不在这里：由 AppController 调 clampBelowMenuBar 统一执行。
        for screen in screens {
            let visible = screen
            let leftDelta = visible.minX - windowFrame.minX
            let rightDelta = visible.maxX - windowFrame.maxX
            let bottomDelta = visible.minY - windowFrame.minY
            let topDelta = visible.maxY - windowFrame.maxY
            if movesTowardEdge(leftDelta, drag: dragDelta.x) {
                considerX(visible.minX, delta: leftDelta, guide: nil)
            }
            if movesTowardEdge(rightDelta, drag: dragDelta.x) {
                considerX(visible.maxX, delta: rightDelta, guide: nil)
            }
            if movesTowardEdge(bottomDelta, drag: dragDelta.y) {
                considerY(visible.minY, delta: bottomDelta, guide: nil)
            }
            if movesTowardEdge(topDelta, drag: dragDelta.y) {
                considerY(visible.maxY, delta: topDelta, guide: nil)
            }
        }

        if let x = bestX { origin.x += x.delta; guides.append(contentsOf: compactGuides(x.guide)) }
        if let y = bestY { origin.y += y.delta; guides.append(contentsOf: compactGuides(y.guide)) }
        return Result(origin: origin, guides: guides)
    }

    private static func compactGuides(_ guide: Guide?) -> [Guide] {
        if let guide { return [guide] } else { return [] }
    }

    /// 屏幕边缘吸附的方向守卫：候选位移与拖动方向同向（或任一为零）时才允许吸附。
    ///
    /// 候选 delta 表示“吸附会把窗口往哪个方向推”；dragDelta 是本帧拖动的实际方向。
    /// 两者相反说明用户正把贴纸拖离这个停靠位，此时不吸附，
    /// 否则阈值带内慢速拖动会被反复拉回，形成拖不出去的“隐形墙”。
    /// 贴纸间对齐不经过此守卫（对齐是对称的期望行为）。
    private static func movesTowardEdge(_ candidateDelta: CGFloat, drag: CGFloat) -> Bool {
        if candidateDelta == 0 || drag == 0 { return true }
        return (candidateDelta > 0) == (drag > 0)
    }

    // 参考线只在两矩形重叠的区间内绘制，避免满屏长线。
    private static func verticalGuide(at x: CGFloat, between a: CGRect, and b: CGRect) -> Guide {
        Guide(axis: .vertical, position: x,
              range: overlapRange(aMin: a.minY, aMax: a.maxY, bMin: b.minY, bMax: b.maxY))
    }

    private static func horizontalGuide(at y: CGFloat, between a: CGRect, and b: CGRect) -> Guide {
        Guide(axis: .horizontal, position: y,
              range: overlapRange(aMin: a.minX, aMax: a.maxX, bMin: b.minX, bMax: b.maxX))
    }

    private static func overlapRange(aMin: CGFloat, aMax: CGFloat, bMin: CGFloat, bMax: CGFloat) -> ClosedRange<CGFloat> {
        let lo = max(aMin, bMin), hi = min(aMax, bMax)
        return lo <= hi ? lo...hi : min(lo, hi)...max(lo, hi)
    }
}

/// 对齐参考线覆盖窗口：拖动吸附时显示蓝色对齐线，松手即隐藏。
///
/// 独立透明窗口，不参与事件（ignoresMouseEvents）、不抢焦点，
/// 层级高于贴纸面板，拖动结束即收起。
final class AlignmentGuideWindow: NSWindow {

    private var guides: [SnapEngine.Guide] = []
    private let guideLayer = GuideLayer()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = guideLayer
        animationBehavior = .none
        alphaValue = 0.9
    }

    /// 展示一组参考线（AppKit 全局坐标）。
    func show(guides: [SnapEngine.Guide]) {
        self.guides = guides
        guard !guides.isEmpty else {
            orderOut(nil)
            return
        }
        // 覆盖窗口铺满包含全部屏幕的联合矩形，简单起见直接用主屏 frame。
        let union = NSScreen.screens.map { $0.frame }.reduce(NSScreen.screens.first?.frame ?? .zero) { $0.union($1) }
        setFrame(union, display: false)
        guideLayer.needsDisplay = true
        orderFrontRegardless()
    }

    func hide() {
        guides = []
        orderOut(nil)
    }

    private final class GuideLayer: NSView {
        override func draw(_ dirtyRect: NSRect) {
            // 与窗口共享坐标系（AppKit 底左），系统蓝参考线。
            let color = NSColor.systemBlue.withAlphaComponent(0.75)
            for guide in guides(of: window as? AlignmentGuideWindow) {
                color.setFill()
                switch guide.axis {
                case .vertical:
                    let rect = CGRect(x: guide.position - 0.75, y: guide.range.lowerBound,
                                      width: 1.5, height: max(2, guide.range.upperBound - guide.range.lowerBound))
                    rect.fill()
                case .horizontal:
                    let rect = CGRect(x: guide.range.lowerBound, y: guide.position - 0.75,
                                      width: max(2, guide.range.upperBound - guide.range.lowerBound), height: 1.5)
                    rect.fill()
                }
            }
        }

        private func guides(of window: AlignmentGuideWindow?) -> [SnapEngine.Guide] {
            window?.guides ?? []
        }
    }
}
