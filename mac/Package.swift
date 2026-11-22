// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Berang",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/gradium-ai/xn-ptts.git", exact: "0.7.1"),
    ],
    targets: [
        .target(name: "TextGrab"),
        .target(name: "Speakable"),
        .executableTarget(name: "berang-grab", dependencies: ["TextGrab"]),
        .executableTarget(name: "page-viewer"),
        .executableTarget(name: "berang-say", dependencies: ["Speakable", .product(name: "ptts", package: "xn-ptts")]),
        .executableTarget(name: "Berang", dependencies: ["TextGrab", "Speakable", .product(name: "ptts", package: "xn-ptts")]),
        .testTarget(name: "TextGrabTests", dependencies: ["TextGrab"]),
        .testTarget(name: "SpeakableTests", dependencies: ["Speakable"]),
    ]
)
