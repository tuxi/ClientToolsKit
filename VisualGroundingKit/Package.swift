// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VisualGroundingKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "VisualGroundingKit",
            targets: ["VisualGroundingKit"]
        ),
    ],
    targets: [
        .target(
            name: "VisualGroundingKit",
            path: "Sources/VisualGroundingKit"
        ),
        .testTarget(
            name: "VisualGroundingKitTests",
            dependencies: ["VisualGroundingKit"],
            path: "Tests/VisualGroundingKitTests"
        )
    ]
)
