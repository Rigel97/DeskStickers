import Foundation

/// 运行时状态导出（自动化 dump 动作的数据层）。
///
/// 从 AppController 拆出：Codable 结构定义与编码是纯数据变换，
/// 通过 Entry 注入所需信息，不反向依赖窗口控制器。
enum RuntimeStateDumper {

    /// 单张贴纸的运行时快照条目（由协调器填充）。
    struct Entry {
        let sticker: Sticker
        /// 纸面矩形（CG 顶左坐标，全局）。
        let paper: CGRect
        /// 窗口矩形（CG 顶左坐标，全局）。
        let window: CGRect
        /// 纸面在画布（快照）中的偏移，便于像素验证。
        let canvasOffset: [CGFloat]
        let level: Int
        let visible: Bool
    }

    // MARK: - JSON 结构（字段名被 e2e 依赖，保持稳定）

    struct DumpSticker: Codable {
        var id: String
        var text: String
        var style: String
        var colorIndex: Int
        var scale: Double
        var fontName: String?
        var fontSize: Double?
        var paper: CGRect
        var window: CGRect
        /// 纸面在画布（快照）中的偏移，便于像素验证。
        var canvasOffset: [CGFloat]
        var level: Int
        var visible: Bool
    }

    struct Dump: Codable {
        var allHidden: Bool
        var pinnedToDesktop: Bool
        var stickers: [DumpSticker]
    }

    /// 把全部贴纸的运行时状态编码写入 url。
    static func write(allHidden: Bool, pinnedToDesktop: Bool, entries: [Entry], to url: URL) {
        let items = entries.map { entry in
            DumpSticker(
                id: entry.sticker.id.uuidString,
                text: entry.sticker.text,
                style: entry.sticker.styleID,
                colorIndex: entry.sticker.colorIndex,
                scale: entry.sticker.scale,
                fontName: entry.sticker.fontName,
                fontSize: entry.sticker.fontSize,
                paper: entry.paper,
                window: entry.window,
                canvasOffset: entry.canvasOffset,
                level: entry.level,
                visible: entry.visible
            )
        }
        let dump = Dump(allHidden: allHidden, pinnedToDesktop: pinnedToDesktop, stickers: items)
        if let data = try? JSONEncoder().encode(dump) {
            try? data.write(to: url)
        }
    }
}
