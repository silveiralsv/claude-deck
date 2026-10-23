// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeDeck"),
        .testTarget(name: "ClaudeDeckTests", dependencies: ["ClaudeDeck"]),
    ]
)
