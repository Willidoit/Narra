// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NarraV2",
    platforms: [.macOS(.v14)],
    dependencies: [
        // STT: whisper.cpp Swift bindings (local fallback)
        // .package(url: "...", from: "..."),
        // LLM: MLX Swift (local fallback)
        // .package(url: "...", from: "..."),
    ],
    targets: [
        .executableTarget(
            name: "NarraV2",
            dependencies: [],
            path: "Sources/NarraV2"
        ),
        .testTarget(
            name: "NarraV2Tests",
            dependencies: ["NarraV2"],
            path: "Tests/NarraV2Tests"
        ),
    ]
)
