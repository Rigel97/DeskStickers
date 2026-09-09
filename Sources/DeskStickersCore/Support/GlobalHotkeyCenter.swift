import AppKit
import Carbon.HIToolbox

/// 全局快捷键定义：Carbon 键码/修饰键（注册用）+ AppKit 等效键（菜单展示用）。
/// 菜单展示与热键注册共用同一份定义，避免两处各自维护后漂移。
struct GlobalHotkeyDefinition {
    /// Carbon 虚拟键码（kVK_ANSI_*）。
    let keyCode: UInt32
    /// Carbon 修饰键掩码（cmdKey / optionKey / controlKey / shiftKey 组合）。
    let carbonModifiers: UInt32
    /// 菜单展示用等效键字符。
    let keyEquivalent: String
    /// 菜单展示用修饰键。
    let equivalentMask: NSEvent.ModifierFlags

    /// 日志/提示用可读描述，如 "⌘⌥P"。
    var display: String {
        var prefix = ""
        if equivalentMask.contains(.control) { prefix += "⌃" }
        if equivalentMask.contains(.option) { prefix += "⌥" }
        if equivalentMask.contains(.shift) { prefix += "⇧" }
        if equivalentMask.contains(.command) { prefix += "⌘" }
        return prefix + keyEquivalent.uppercased()
    }
}

/// 应用级全局快捷键的唯一来源。
enum AppHotkeys {
    /// ⌥⌘\ 显示/隐藏全部贴纸——应用内等效键是 ⌘\，加 ⌥ 后全局生效。
    static let toggleVisibility = GlobalHotkeyDefinition(
        keyCode: UInt32(kVK_ANSI_Backslash),
        carbonModifiers: UInt32(cmdKey | optionKey),
        keyEquivalent: "\\",
        equivalentMask: [.command, .option]
    )
    /// ⌥⌘P 鼠标穿透——贴纸保持可见，点击穿到下层窗口。
    static let toggleClickThrough = GlobalHotkeyDefinition(
        keyCode: UInt32(kVK_ANSI_P),
        carbonModifiers: UInt32(cmdKey | optionKey),
        keyEquivalent: "p",
        equivalentMask: [.command, .option]
    )
    /// ⌥⌘N 新建贴纸——任何应用下直接弹出创建器。
    static let newSticker = GlobalHotkeyDefinition(
        keyCode: UInt32(kVK_ANSI_N),
        carbonModifiers: UInt32(cmdKey | optionKey),
        keyEquivalent: "n",
        equivalentMask: [.command, .option]
    )
    /// ⌥⌘Z 全局撤销——贴纸是非激活面板，用户刚删完贴纸时⌘Z 往往发给了别的应用；
    /// 这个热键保证「删除后立刻反悔」在任何应用下都有效。
    static let undo = GlobalHotkeyDefinition(
        keyCode: UInt32(kVK_ANSI_Z),
        carbonModifiers: UInt32(cmdKey | optionKey),
        keyEquivalent: "z",
        equivalentMask: [.command, .option]
    )
    /// ⌥⌘V 从剪贴板新建贴纸——复制文字秒变贴纸，最高频路径缩短到一次按键。
    static let newFromClipboard = GlobalHotkeyDefinition(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(cmdKey | optionKey),
        keyEquivalent: "v",
        equivalentMask: [.command, .option]
    )
}

/// 单把全局快捷键：Carbon RegisterEventHotKey 封装。
///
/// 为什么不用 NSEvent.addGlobalMonitorForEvents：
/// 键盘事件的全局监听需要辅助功能权限，而 Carbon 热键不需要，
/// 且应用不在前台时同样派发（在主线程事件循环）。
final class GlobalHotkeyCenter {

    /// 'STKR'：热键事件签名，用于在回调里过滤只属于自己的事件。
    private static let signature: OSType = 0x53_54_4B_52

    private let hotKeyID: EventHotKeyID
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// 注册失败（如组合键已被其他应用占用）时返回 nil。
    init?(definition: GlobalHotkeyDefinition, id: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        self.hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        self.hotKeyRef = nil
        self.eventHandler = nil

        // InstallEventHandler 的回调是 C 函数指针，无法捕获上下文：
        // 通过 userData 桥接回实例，再用 hotKeyID 过滤事件归属。
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let center = Unmanaged<GlobalHotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr,
                  hotKeyID.signature == center.hotKeyID.signature,
                  hotKeyID.id == center.hotKeyID.id else { return noErr }
            center.fire()
            return noErr
        }

        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                                  selfPointer, &eventHandler) == noErr else {
            eventHandler = nil
            return nil
        }
        var registered: EventHotKeyRef?
        guard RegisterEventHotKey(definition.keyCode, definition.carbonModifiers, hotKeyID,
                                  GetApplicationEventTarget(), 0, &registered) == noErr,
              let registered else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            self.eventHandler = nil
            return nil
        }
        hotKeyRef = registered
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// 热键命中（Carbon 在主线程派发，可直接操作 UI）。
    fileprivate func fire() {
        handler()
    }
}
