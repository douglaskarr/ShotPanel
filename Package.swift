// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShotPanel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ShotPanel", path: "Sources/ShotPanel")
    ]
)
