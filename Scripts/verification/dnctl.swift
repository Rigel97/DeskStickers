import Foundation

// 向桌面贴纸应用发送自动化指令（需应用以 --automation 启动）
// 用法: dnctl <action> [key=value ...]
// 动作: create / move / resize / setStyle / setText / delete / deleteAll
//       hideAll / showAll / snapshot / dump / flush
let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: dnctl <action> [key=value ...]")
    exit(1)
}
let action = args[1]
var info: [String: String] = [:]
for pair in args.dropFirst(2) {
    let kv = pair.split(separator: "=", maxSplits: 1)
    if kv.count == 2 {
        info[String(kv[0])] = String(kv[1]).replacingOccurrences(of: "\\n", with: "\n")
    }
}
DistributedNotificationCenter.default().postNotificationName(
    NSNotification.Name("com.deskstickers.automation.\(action)"),
    object: nil,
    userInfo: info,
    deliverImmediately: true
)
print("SENT \(action) \(info)")
