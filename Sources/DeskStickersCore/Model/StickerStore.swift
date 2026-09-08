import Foundation

/// 持久化快照：版本号 + 全局隐藏/层级标记 + 贴纸列表。
public struct StickerStoreSnapshot: Codable, Equatable {
    public var version: Int
    public var allHidden: Bool
    /// 钉在桌面模式：贴纸置于桌面层（普通窗口之下），不再悬浮遮挡内容。
    public var pinnedToDesktop: Bool
    public var stickers: [Sticker]

    public init(version: Int = 1, allHidden: Bool = false, pinnedToDesktop: Bool = false, stickers: [Sticker] = []) {
        self.version = version
        self.allHidden = allHidden
        self.pinnedToDesktop = pinnedToDesktop
        self.stickers = stickers
    }

    private enum CodingKeys: String, CodingKey {
        case version, allHidden, pinnedToDesktop, stickers
    }

    /// 旧版本状态文件没有 pinnedToDesktop 字段，解码时取默认值。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        allHidden = try c.decode(Bool.self, forKey: .allHidden)
        pinnedToDesktop = try c.decodeIfPresent(Bool.self, forKey: .pinnedToDesktop) ?? false
        stickers = try c.decode([Sticker].self, forKey: .stickers)
    }
}

/// 贴纸存储：JSON 原子写入 + 防抖自动保存。
public final class StickerStore {

    public static let defaultDirectoryName = "DeskStickers"
    public static let defaultFileName = "stickers.json"

    public let fileURL: URL
    public private(set) var snapshot: StickerStoreSnapshot
    /// 首次启动（存储文件不存在）。
    public let isFirstLaunch: Bool

    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 0.4
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil) {
        let dir = directory ?? StickerStore.defaultDirectory()
        // 自定义目录（如 --state-dir）可能不存在，先确保建好再读写。
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(Self.defaultFileName)

        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var firstLaunch = false
        var loaded: StickerStoreSnapshot
        if let data = try? Data(contentsOf: fileURL) {
            if let snapshot = try? decoder.decode(StickerStoreSnapshot.self, from: data) {
                loaded = snapshot
            } else {
                // 文件损坏：保留现场并从空状态开始。
                let backup = dir.appendingPathComponent("stickers.corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? data.write(to: backup)
                Log.error("存储文件损坏，已备份至 \(backup.path)，从空状态启动")
                loaded = StickerStoreSnapshot()
            }
        } else {
            firstLaunch = true
            loaded = StickerStoreSnapshot()
        }
        self.snapshot = loaded
        self.isFirstLaunch = firstLaunch
    }

    public static func defaultDirectory() -> URL {
        let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(defaultDirectoryName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 读写

    public func loadFresh() {
        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? decoder.decode(StickerStoreSnapshot.self, from: data) {
            self.snapshot = snapshot
        }
    }

    /// 立即写盘（原子写）。
    public func persistNow() {
        saveTimer?.invalidate()
        saveTimer = nil
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.error("保存失败: \(error.localizedDescription)")
        }
    }

    /// 防抖保存：合并高频变更（拖动、打字）。
    public func persistSoon() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            self?.persistNow()
        }
    }

    // MARK: - 变更

    public var stickers: [Sticker] {
        snapshot.stickers
    }

    public var allHidden: Bool {
        snapshot.allHidden
    }

    public var pinnedToDesktop: Bool {
        snapshot.pinnedToDesktop
    }

    public func upsert(_ sticker: Sticker) {
        var updated = sticker
        updated.updatedAt = Date()
        if let index = snapshot.stickers.firstIndex(where: { $0.id == sticker.id }) {
            snapshot.stickers[index] = updated
        } else {
            snapshot.stickers.append(updated)
        }
        persistSoon()
    }

    public func remove(id: UUID) {
        snapshot.stickers.removeAll { $0.id == id }
        persistSoon()
    }

    /// 把交互过的贴纸移到列表末尾（列表顺序即恢复时的层级顺序）。
    public func moveToEnd(id: UUID) {
        guard let index = snapshot.stickers.firstIndex(where: { $0.id == id }),
              index != snapshot.stickers.count - 1 else { return }
        let sticker = snapshot.stickers.remove(at: index)
        snapshot.stickers.append(sticker)
        persistSoon()
    }

    public func setAllHidden(_ hidden: Bool) {
        snapshot.allHidden = hidden
        persistSoon()
    }

    public func setPinnedToDesktop(_ pinned: Bool) {
        snapshot.pinnedToDesktop = pinned
        persistSoon()
    }

    /// 供测试与自动化读取。
    public func sticker(id: UUID) -> Sticker? {
        snapshot.stickers.first { $0.id == id }
    }
}
