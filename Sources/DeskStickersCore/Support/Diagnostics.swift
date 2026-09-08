import Foundation

/// 统一诊断输出：stderr + 时间戳，便于运行验证时检查错误。
public enum Log {
    public static let subsystem = "com.deskstickers.mac"

    public static func info(_ message: String) {
        emit("INFO", message)
    }

    public static func warn(_ message: String) {
        emit("WARN", message)
    }

    public static func error(_ message: String) {
        emit("ERROR", message)
    }

    private static func emit(_ level: String, _ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardError.write(Data("[\(stamp)] [DeskStickers][\(level)] \(message)\n".utf8))
    }
}

/// 捕获未处理异常，写入 stderr（验证时用于排查崩溃）。
public func installUncaughtExceptionHandler() {
    NSSetUncaughtExceptionHandler { exception in
        let details = """
        UNCAUGHT EXCEPTION: \(exception.name.rawValue)
        reason: \(exception.reason ?? "-")
        \(exception.callStackSymbols.joined(separator: "\n"))
        """
        FileHandle.standardError.write(Data("[DeskStickers][FATAL] \(details)\n".utf8))
    }
}
