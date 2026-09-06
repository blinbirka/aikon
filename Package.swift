// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aikon",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Aikon", path: "Sources/Aikon", resources: [.process("Resources")]),
        .testTarget(name: "AikonTests", dependencies: ["Aikon"], path: "Tests/AikonTests")
    ]
)
