// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenCoreGraphics",
    products: [
        .library(
            name: "OpenCoreGraphics",
            targets: ["OpenCoreGraphics"]
        ),
        .executable(
            name: "OpenCoreGraphicsSample",
            targets: ["OpenCoreGraphicsSample"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/helbertgs/OpenGLAD", branch: "main"),
        .package(url: "https://github.com/helbertgs/OpenGLFW", branch: "main"),
        .package(url: "https://github.com/helbertgs/OpenSTB", branch: "main")
    ],
    targets: [
        .target(
            name: "OpenCoreGraphics",
            dependencies: [
                .product(name: "OpenGLAD", package: "OpenGLAD"),
                .product(name: "OpenGLFW", package: "OpenGLFW"),
                .product(name: "OpenSTB", package: "OpenSTB")
            ]
        ),
        .executableTarget(
            name: "OpenCoreGraphicsSample",
            dependencies: [
                "OpenCoreGraphics"
            ]
        ),
        .testTarget(
            name: "OpenCoreGraphicsTests",
            dependencies: ["OpenCoreGraphics"]
        ),
    ]
)
