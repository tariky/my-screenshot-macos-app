// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Screenshot",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ScreenshotCore"),
        .executableTarget(name: "Screenshot", dependencies: ["ScreenshotCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["ScreenshotCore"]),
    ]
)
