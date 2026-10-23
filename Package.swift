// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeDeck",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "ClaudeDeck"),
        .testTarget(name: "ClaudeDeckTests", dependencies: ["ClaudeDeck"]),
    ],
    swiftLanguageModes: [.v5]
)
