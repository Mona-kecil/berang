// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "PocketSpike",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", exact: "0.2.1"),
    ],
    targets: [
        .executableTarget(name: "pocket-spike", dependencies: [
            .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
            .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
        ]),
    ]
)
