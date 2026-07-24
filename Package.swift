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
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ClientToolsKit",
            targets: ["ClientToolsKit"]
        ),
    ],
    dependencies: [
        .package(path: "../ClientToolProtocol"),
        .package(path: "VisualGroundingKit"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ClientToolsKit",
            dependencies: [
                .product(name: "ClientToolProtocol", package: "ClientToolProtocol"),
                .product(name: "VisualGroundingKit", package: "VisualGroundingKit"),
            ]
        ),
        .testTarget(
            name: "ClientToolsKitTests",
            dependencies: ["ClientToolsKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
