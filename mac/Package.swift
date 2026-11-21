// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Berang",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TextGrab"),
        .executableTarget(name: "berang-grab", dependencies: ["TextGrab"]),
        .testTarget(name: "TextGrabTests", dependencies: ["TextGrab"]),
    ]
)
