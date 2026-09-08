// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeskStickers",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "DeskStickersCore",
            path: "Sources/DeskStickersCore"
        ),
        .executableTarget(
            name: "DeskStickers",
            dependencies: ["DeskStickersCore"],
            path: "Sources/DeskStickers"
        ),
        // 本机 CLT 环境缺少 XCTest 且 swift-testing 集成不可用，
        // 采用自建测试执行器（swift run deskstickers-selftest）。
        .executableTarget(
            name: "DeskStickersSelfTest",
            dependencies: ["DeskStickersCore"],
            path: "Sources/DeskStickersSelfTest"
        )
    ],
    swiftLanguageModes: [.v5]
)
