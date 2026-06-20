// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Narra",
    platforms: [.macOS(.v15)],
    dependencies: [
        // STT: WhisperKit (local on-device transcription via Apple Neural Engine)
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        // STT: Parakeet (FluidAudio's CoreML port of NVIDIA Parakeet TDT,
        // exposed through UnifiedAsrManager).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0"),
    ],
    targets: [
        .executableTarget(
            name: "Narra",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
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
