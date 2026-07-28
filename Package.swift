// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClientToolsKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ClientToolsKit",
            targets: ["ClientToolsKit"]
        ),
        .library(
            name: "VisualGroundingKit",
            targets: ["VisualGroundingKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/tuxi/ClientToolProtocol", branch: "main"),
    ],
    targets: [
        .target(
            name: "ClientToolsKit",
            dependencies: [
                .product(name: "ClientToolProtocol", package: "ClientToolProtocol"),
                "VisualGroundingKit",
            ]
        ),
        .target(
            name: "VisualGroundingKit",
            path: "Sources/VisualGroundingKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ClientToolsKitTests",
            dependencies: ["ClientToolsKit"]
        ),
        .testTarget(
            name: "VisualGroundingKitTests",
            dependencies: ["VisualGroundingKit"],
            path: "Tests/VisualGroundingKitTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
