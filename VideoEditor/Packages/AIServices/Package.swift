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
    ],
    targets: [
        .target(
            name: "AIServices",
            dependencies: ["EditorCore"],
            path: "Sources/AIServices"
        ),
        .testTarget(
            name: "AIServicesTests",
            dependencies: ["AIServices"],
            path: "Tests/AIServicesTests"
        ),
    ]
)
