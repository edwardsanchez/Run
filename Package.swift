// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RunCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "RunCore", targets: ["RunCore"])],
    targets: [
        .target(
            name: "RunCore",
            path: "Run",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "Run.icon",
                "RunApp.swift",
                "AppStore.swift",
                "XcodeClient.swift",
                "StatusItemController.swift",
            ]
        ),
        .testTarget(name: "RunCoreTests", dependencies: ["RunCore"]),
    ]
)
