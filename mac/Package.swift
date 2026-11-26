// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Berang",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/gradium-ai/xn-ptts.git", exact: "0.7.1"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", exact: "0.2.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.33.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", exact: "1.0.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "TextGrab"),
        .target(name: "Speakable"),
        .target(name: "Keys"),
        .target(name: "Kitten", dependencies: [
            .product(name: "MLX", package: "mlx-swift"), .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLXFast", package: "mlx-swift"), .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            .product(name: "MLXAudioTTS", package: "mlx-audio-swift"), .product(name: "HuggingFace", package: "swift-huggingface"),
        ]),
        .executableTarget(name: "berang-grab", dependencies: ["TextGrab"]),
        .executableTarget(name: "page-viewer"),
        .executableTarget(name: "berang-say", dependencies: [
            "Speakable", "Kitten", .product(name: "ptts", package: "xn-ptts"),
            .product(name: "MLXAudioTTS", package: "mlx-audio-swift"), .product(name: "HuggingFace", package: "swift-huggingface"),
        ]),
        .executableTarget(name: "Berang", dependencies: [
            "TextGrab", "Speakable", "Kitten", "Keys", .product(name: "ptts", package: "xn-ptts"),
            .product(name: "MLXAudioTTS", package: "mlx-audio-swift"), .product(name: "HuggingFace", package: "swift-huggingface"),
            .product(name: "Sparkle", package: "Sparkle"),
        ]),
        .testTarget(name: "TextGrabTests", dependencies: ["TextGrab"], exclude: ["Pages"]),
        .testTarget(name: "SpeakableTests", dependencies: ["Speakable"]),
        .testTarget(name: "KeysTests", dependencies: ["Keys"]),
    ]
)
