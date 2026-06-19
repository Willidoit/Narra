// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Narra",
    platforms: [.macOS(.v15)],
    dependencies: [
        // STT: WhisperKit (local on-device transcription via Apple Neural Engine)
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        // STT: whisper.cpp pending — ggerganov/whisper.cpp does not publish a
        //   usable root Package.swift. Plan: vendor the C sources into
        //   Sources/CWhisper/ as a SwiftPM C target. Until that lands,
        //   WhisperCppTranscriptionService is a stub that throws.
        // LLM: MLX Swift (local fallback)
        // .package(url: "...", from: "..."),
    ],
    targets: [
        .executableTarget(
            name: "Narra",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/Narra",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NarraTests",
            dependencies: ["Narra"],
            path: "Tests/NarraTests"
        ),
    ]
)
