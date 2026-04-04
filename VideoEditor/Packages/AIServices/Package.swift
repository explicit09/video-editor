// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIServices",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AIServices", targets: ["AIServices"]),
    ],
    dependencies: [
        .package(path: "../EditorCore"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "AIServices",
            dependencies: ["EditorCore", "WhisperKit"],
            path: "Sources/AIServices"
        ),
        .testTarget(
            name: "AIServicesTests",
            dependencies: ["AIServices"],
            path: "Tests/AIServicesTests"
        ),
    ]
)
