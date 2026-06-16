// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NarraV2",
    platforms: [.macOS(.v14)],
    dependencies: [
        // STT: WhisperKit (local on-device transcription via Apple Neural Engine)
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        // LLM: MLX Swift (local fallback)
        // .package(url: "...", from: "..."),
    ],
    targets: [
        .executableTarget(
            name: "NarraV2",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/NarraV2"
        ),
        .testTarget(
            name: "NarraV2Tests",
            dependencies: ["NarraV2"],
            path: "Tests/NarraV2Tests"
        ),
    ]
)
