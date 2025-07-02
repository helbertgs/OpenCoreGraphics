// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if os(macOS)
let branch = "macos"
#else
let branch = "main"
#endif

let package = Package(
    name: "OpenCoreGraphics",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "OpenCoreGraphics",
            targets: ["OpenCoreGraphics"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/helbertgs/OpenGLAD", branch: branch),
        .package(url: "https://github.com/helbertgs/OpenGLFW", branch: "main"),
        .package(url: "https://github.com/helbertgs/OpenSTB", revision: "1.0")
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
        .testTarget(
            name: "OpenCoreGraphicsTests",
            dependencies: ["OpenCoreGraphics"]
        ),
    ]
)
