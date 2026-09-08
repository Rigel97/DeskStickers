import AppKit
import DeskStickersCore

// 轻量测试执行器：`swift run DeskStickersSelfTest`
// 断言失败或测试抛错时以非零码退出。

var passed = 0
var failed = 0
var currentTest = ""

func expect(_ condition: Bool, _ message: String = "") {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("  ✗ 断言失败 [\(currentTest)] \(message)")
    }
}

func expectNear(_ a: Double, _ b: Double, _ tolerance: Double = 0.01, _ message: String = "") {
    expect(abs(a - b) <= tolerance, "\(message) (\(a) ≈ \(b))")
}

func test(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    do {
        try body()
        print("✓ \(name)")
    } catch {
        failed += 1
        print("  ✗ 测试抛出异常 [\(name)]: \(error)")
    }
}

// MARK: - 工具

private func tempStoreDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("deskstickers-selftest-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeSticker(text: String = "你好，桌面", style: String = "sticky") -> Sticker {
    Sticker(text: text, styleID: style, colorIndex: 0,
            paperX: 100, paperY: 200, width: 220, height: 160)
}

private func luminance(_ color: NSColor) -> CGFloat {
    let rgb = color.usingColorSpace(.deviceRGB) ?? .white
    return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
}

// MARK: - 持久化

var storeDir: URL = URL(fileURLWithPath: "/tmp")

test("存储-首次启动") {
    let dir = tempStoreDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = StickerStore(directory: dir)
    expect(store.isFirstLaunch, "文件缺失时应判定为首次启动")
    expect(store.stickers.isEmpty)
    expect(!store.allHidden)
}

test("存储-读写往返") {
    let dir = tempStoreDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = StickerStore(directory: dir)
    let sticker = makeSticker()
    store.upsert(sticker)
    store.upsert(makeSticker(text: "第二张", style: "notebook"))
    store.persistNow()

    let reloaded = StickerStore(directory: dir)
    expect(!reloaded.isFirstLaunch)
    expect(reloaded.stickers.count == 2)
    let loaded = reloaded.sticker(id: sticker.id)
    expect(loaded?.text == "你好，桌面")
    expect(loaded?.styleID == "sticky")
    expect(loaded?.paperFrame == sticker.paperFrame, "纸面矩形应完整往返")
}

test("存储-更新保持单一副本") {
    let dir = tempStoreDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = StickerStore(directory: dir)
    var sticker = makeSticker()
    store.upsert(sticker)
    sticker.text = "改过的文字"
    sticker.paperX = 333
    store.upsert(sticker)
    store.persistNow()

    let reloaded = StickerStore(directory: dir)
    expect(reloaded.stickers.count == 1, "同 id upsert 不应产生副本")
    expect(reloaded.sticker(id: sticker.id)?.text == "改过的文字")
    expectNear(reloaded.sticker(id: sticker.id)?.paperX ?? 0, 333)
}

test("存储-防抖合并高频写入") {
    let dir = tempStoreDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = StickerStore(directory: dir)
    // 模拟拖拽：同一防抖窗口内的连续变更不应逐次写盘
    var sticker = makeSticker()
    for x in stride(from: 100.0, through: 200.0, by: 10) {
        sticker.paperX = x
        store.upsert(sticker)
    }
    // 防抖窗口（0.4s）内文件尚未落盘或内容未含最新值
    if let data = try? Data(contentsOf: store.fileURL),
       let snapshot = try? JSONDecoder().decode(StickerStoreSnapshot.self, from: data) {
        expect(snapshot.stickers.first?.paperX != 200, "防抖窗口内不应立即写入最新值")
    }
    // 防抖到期后（跑 run loop）应落盘且为最终值
    RunLoop.main.run(until: Date().addingTimeInterval(0.7))
    let reloaded = StickerStore(directory: dir)
    expect(reloaded.stickers.count == 1)
    expectNear(reloaded.sticker(id: sticker.id)?.paperX ?? 0, 200, 0.01, "防抖后落盘的是最终值")
}

test("存储-删除") {
    let dir = tempStoreDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = StickerStore(directory: dir)
    let sticker = makeSticker()
    store.upsert(sticker)
    store.remove(id: sticker.id)
    store.persistNow()
    expect(StickerStore(directory: dir).stickers.isEmpty)
}

test("存储-损坏文件回退与备份") {
    let dir = tempStoreDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let fileURL = dir.appendingPathComponent(StickerStore.defaultFileName)
    try Data("这不是合法 JSON {{{".utf8).write(to: fileURL)
    let store = StickerStore(directory: dir)
    expect(store.stickers.isEmpty, "损坏文件应回退为空状态")
    let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .filter { $0.hasPrefix("stickers.corrupt-") }
    expect(backups.count == 1, "损坏现场应被备份")
}

test("存储-全局隐藏标记持久化") {
    let dir = tempStoreDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = StickerStore(directory: dir)
    store.setAllHidden(true)
    store.persistNow()
    expect(StickerStore(directory: dir).allHidden)
}

test("存储-moveToEnd 调整层级顺序") {
    let dir = tempStoreDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = StickerStore(directory: dir)
    let first = makeSticker(text: "第一")
    let second = makeSticker(text: "第二")
    store.upsert(first)
    store.upsert(second)
    store.moveToEnd(id: first.id)
    expect(store.stickers.map { $0.id } == [second.id, first.id])
    store.moveToEnd(id: first.id)
    expect(store.stickers.map { $0.id } == [second.id, first.id], "已在末尾时不应变化")
}

test("存储-JSON 字段名稳定") {
    let sticker = Sticker(text: "字段稳定性", styleID: "blackboard", colorIndex: 2,
                          paperX: 10.5, paperY: 20.5, width: 250, height: 180,
                          scale: 1.2, fontName: "SongtiSC-Regular", fontSize: 16)
    let json = try JSONEncoder().encode(StickerStoreSnapshot(stickers: [sticker]))
    let text = String(data: json, encoding: .utf8) ?? ""
    expect(text.contains("\"style\""), "字段名应为 style")
    expect(text.contains("\"colorIndex\""))
    expect(text.contains("\"paperX\""))
    expect(text.contains("\"paperY\""))
    expect(text.contains("\"width\""))
    expect(text.contains("\"height\""))
    expect(text.contains("\"scale\""))
    expect(text.contains("\"fontName\""))
    expect(text.contains("\"fontSize\""))
}

// MARK: - 等比缩放与字体覆盖

test("缩放-scaled 等比缩放全部度量") {
    let base = StickerStyles.style(id: "sticky")
    let scaled = base.scaled(by: 2)
    expect(abs(scaled.fontSize - base.fontSize * 2) < 0.01, "字号 ×2")
    expect(abs(scaled.textInsets.top - base.textInsets.top * 2) < 0.01, "内边距 ×2")
    expect(abs(scaled.cornerRadius - base.cornerRadius * 2) < 0.01, "圆角 ×2")
    expect(abs(scaled.shadow.blur - base.shadow.blur * 2) < 0.01, "阴影 ×2")
    expect(abs(scaled.defaultWidth - base.defaultWidth * 2) < 0.01, "默认宽 ×2")
    expect(scaled.variants.count == base.variants.count, "变体不变")
    expect(scaled.id == base.id, "id 不变")
}

test("缩放-字体族与字号覆盖") {
    let base = StickerStyles.style(id: "sticky")
    let overridden = base.scaled(by: 1.5, fontName: "KaitiSC-Regular", fontSize: 20)
    expect(overridden.fontNames.first == "KaitiSC-Regular", "覆盖字体排最前")
    expect(overridden.fontNames.contains(base.fontNames.first ?? ""), "原回退链保留")
    expect(abs(overridden.fontSize - 20) < 0.01, "字号覆盖为绝对值，不吃缩放")
    let onlyFont = base.scaled(by: 0.5, fontName: nil, fontSize: nil)
    expect(abs(onlyFont.fontSize - base.fontSize * 0.5) < 0.01, "无覆盖时字号随缩放")
}

test("缩放-effectiveStyle 反映贴纸状态") {
    var sticker = Sticker(text: "x", styleID: "sticky", paperX: 0, paperY: 0, width: 220, height: 100)
    expect(sticker.effectiveStyle().fontSize == StickerStyles.sticky.fontSize, "默认 1.0 不缩放")
    sticker.scale = 2.0
    expect(abs(sticker.effectiveStyle().fontSize - StickerStyles.sticky.fontSize * 2) < 0.01)
    sticker.fontSize = 30
    expect(abs(sticker.effectiveStyle().fontSize - 30) < 0.01, "字号覆盖优先于缩放")
    sticker.fontName = "SongtiSC-Regular"
    expect(sticker.effectiveStyle().fontNames.first == "SongtiSC-Regular")
}

test("缩放-旧版 JSON 缺字段回退默认值") {
    let sticker = Sticker(text: "兼容", styleID: "sticky", paperX: 1, paperY: 2, width: 220, height: 90,
                         scale: 1.6, fontName: "KaitiSC-Regular", fontSize: 18)
    let json = try JSONEncoder().encode(StickerStoreSnapshot(stickers: [sticker]))
    // 模拟旧版本状态文件：剥掉新增字段
    var object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
    var stickers = object["stickers"] as! [[String: Any]]
    stickers[0].removeValue(forKey: "scale")
    stickers[0].removeValue(forKey: "fontName")
    stickers[0].removeValue(forKey: "fontSize")
    object["stickers"] = stickers
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(StickerStoreSnapshot.self, from: legacy)
    let restored = decoded.stickers[0]
    expect(restored.scale == 1.0, "scale 默认 1.0")
    expect(restored.fontName == nil, "fontName 默认 nil")
    expect(restored.fontSize == nil, "fontSize 默认 nil")
    expect(restored.text == "兼容", "其余字段不受影响")
}

// MARK: - 风格注册表

test("风格-8 种内置且顺序稳定") {
    expect(StickerStyles.all.count == 8)
    let expected = ["notebook", "handwritten", "sticky", "minimal", "vintage", "blackboard", "cute", "mono"]
    expect(StickerStyles.all.map { $0.id } == expected)
}

test("风格-id 唯一") {
    let ids = StickerStyles.all.map { $0.id }
    expect(ids.count == Set(ids).count)
}

test("风格-未知 id 回退便利贴") {
    expect(StickerStyles.style(id: "nonexistent").id == "sticky")
}

test("风格-字体回退链全部可解析") {
    for style in StickerStyles.all {
        expect(FontBook.isResolvable(style.fontNames), "\(style.id): \(style.fontNames)")
    }
}

test("风格-各风格主字体彼此不同") {
    let primaryFonts = StickerStyles.all.map { $0.fontNames.first ?? "" }
    expect(Set(primaryFonts).count == primaryFonts.count)
}

test("风格-墨色对比度充足") {
    for style in StickerStyles.all {
        expect(style.variants.count >= 1, "\(style.id) 至少一种颜色变体")
        for variant in style.variants {
            let inkLum = luminance(variant.ink)
            let bgLum = (luminance(variant.top) + luminance(variant.bottom)) / 2
            expect(abs(inkLum - bgLum) > 0.35, "\(style.id)/\(variant.name)")
        }
    }
}

test("风格-几何规格合理") {
    for style in StickerStyles.all {
        expect(style.minWidth < style.defaultWidth, "\(style.id) minWidth")
        expect(style.defaultWidth < style.maxWidth, "\(style.id) maxWidth")
        let insets = style.outerInsets
        expect(insets.top >= 16, "\(style.id) 顶部留白应容纳工具栏")
        expect(insets.left >= 10 && insets.right >= 10, "\(style.id) 左右留白")
        expect(insets.bottom >= 12, "\(style.id) 底部留白")
        expect(style.textWidth(forPaperWidth: style.defaultWidth) > 60, "\(style.id) 文字宽度")
    }
}

test("风格-便利贴提供 4 色变体") {
    expect(StickerStyles.style(id: "sticky").variants.count >= 4)
}

test("风格-预览渲染器可出图") {
    for style in StickerStyles.all {
        let image = StickerPreviewRenderer.render(style: style, colorIndex: 0, text: "预览测试")
        expect(image.size.width > 50, "\(style.id) 宽度")
        expect(image.size.height > 30, "\(style.id) 高度")
        expect(image.representations.first != nil, "\(style.id) representation")
    }
}

test("风格-空/短/长文案均正常渲染") {
    let longText = "这是一段比较长的测试文字，用来验证多行换行之后纸面高度能够自适应增长，不应崩溃也不应裁切。"
    for style in StickerStyles.all {
        for text in ["", "短", longText] {
            let image = StickerPreviewRenderer.render(style: style, colorIndex: 0, text: text)
            expect(image.size.width > 50 && image.size.height > 30, "\(style.id)/\(text.count)")
        }
    }
}

// MARK: - 文字引擎

test("文字-多行高度随行数增长") {
    let style = StickerStyles.sticky
    let width = style.textWidth(forPaperWidth: style.defaultWidth)
    let one = StickerTextEngine.measuredTextHeight(
        StickerTextEngine.attributed("一行文字", style: style, colorIndex: 0), width: width)
    let three = StickerTextEngine.measuredTextHeight(
        StickerTextEngine.attributed("一行文字\n第二行\n第三行", style: style, colorIndex: 0), width: width)
    expect(one > 0)
    expect(three > one * 2.2, "三行 ≈ 单行三倍 (\(one) -> \(three))")
}

test("文字-纸面高度包含内边距") {
    let style = StickerStyles.minimal
    let height = StickerTextEngine.paperHeight(
        for: "测试", style: style, colorIndex: 0,
        paperWidth: style.defaultWidth, maxHeight: 10_000)
    expect(height >= style.textInsets.top + style.textInsets.bottom)
    expect(height >= style.minHeight(forTextHeight: 0))
}

test("文字-纸面高度钳制上限") {
    let style = StickerStyles.notebook
    let veryLong = String(repeating: "很长的一段文字，", count: 200)
    let height = StickerTextEngine.paperHeight(
        for: veryLong, style: style, colorIndex: 0,
        paperWidth: style.defaultWidth, maxHeight: 400)
    expect(height <= 400)
}

test("文字-空文案高度合理") {
    for style in StickerStyles.all {
        let height = StickerTextEngine.paperHeight(
            for: "", style: style, colorIndex: 0,
            paperWidth: style.defaultWidth, maxHeight: 10_000)
        expect(height > 40, "\(style.id) 过小: \(height)")
        expect(height < 160, "\(style.id) 过大: \(height)")
    }
}

test("文字-属性携带风格字体与段落") {
    for style in StickerStyles.all {
        let attrs = StickerTextEngine.attributes(for: style, colorIndex: 0)
        let font = attrs[.font] as? NSFont
        expect(font != nil, "\(style.id) 字体")
        expect(font?.fontName == style.font.fontName, "\(style.id) 字体一致")
        expect(attrs[.paragraphStyle] != nil, "\(style.id) 段落")
    }
}

// MARK: - 屏幕几何

test("几何-越界矩形拉回") {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let outside = CGRect(x: 1200, y: 900, width: 200, height: 100)
    expect(bounds.contains(ScreenGeometry.clampFrame(outside, into: bounds)))
}

test("几何-界内矩形保持不变") {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let inside = CGRect(x: 100, y: 100, width: 200, height: 100)
    expect(ScreenGeometry.clampFrame(inside, into: bounds) == inside)
}

test("几何-远屏贴纸拉回主屏") {
    let rescued = ScreenGeometry.rescueFrame(CGRect(x: 90000, y: 90000, width: 220, height: 160))
    expect(ScreenGeometry.primaryVisibleFrame().intersects(rescued))
}

test("几何-级联位置避开重叠且在屏内") {
    let visible = ScreenGeometry.primaryVisibleFrame()
    let existing = [CGRect(x: visible.midX - 110, y: visible.midY - 80, width: 220, height: 160)]
    let origin = ScreenGeometry.cascadeOrigin(existingFrames: existing, size: CGSize(width: 220, height: 160))
    let candidate = CGRect(origin: origin, size: CGSize(width: 220, height: 160))
    expect(!existing[0].intersects(candidate), "应避开已有贴纸")
    expect(visible.insetBy(dx: 2, dy: 2).contains(candidate), "应在可见区域内")
}

test("几何-CG 顶左坐标换算保持尺寸") {
    let frame = CGRect(x: 120, y: 240, width: 300, height: 200)
    let cg = ScreenGeometry.cgTopLeftRect(frame)
    expectNear(cg.width, 300)
    expectNear(cg.height, 200)
}

// MARK: - 汇总

print("")
print("========================================")
print("通过 \(passed) 项断言，失败 \(failed) 项，共 \(passed + failed) 项")
if failed > 0 {
    print("测试失败 ❌")
    exit(1)
} else {
    print("全部测试通过 ✅")
    exit(0)
}
