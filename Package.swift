// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenCoreGraphics",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "OpenCoreGraphics",
            targets: ["OpenCoreGraphics"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/helbertgs/OpenGLAD", revision: "f7e045c6b10f96c6e35ee8dec39c6194ebf57020"),
        .package(url: "https://github.com/helbertgs/OpenGLFW", revision: "fa6ea9f17f321ba759146b27687816ec7baf5b1a"),
        .package(url: "https://github.com/helbertgs/OpenSTB", revision: "ec0baf3213cb9f89641eb336ceb20d130bba8fee")
    ],
    targets: [
        .target(
            name: "OpenCoreGraphics",
            dependencies: [
                .product(name: "OpenGLAD", package: "OpenGLAD"),
                .product(name: "OpenGLFW", package: "OpenGLFW"),
                .product(name: "OpenSTB", package: "OpenSTB"),
                "OpenCoreGraphicsSTB"
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .target(
            name: "OpenCoreGraphicsSTB",
            publicHeadersPath: "include"
        ),
        .target(
            name: "OpenCoreGraphicsGLTestBootstrap",
            path: "Tests/OpenCoreGraphicsGLTestBootstrap",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("AppKit", .when(platforms: [.macOS]))]
        ),
        .executableTarget(
            name: "OpenCoreGraphicsSample",
            dependencies: [
                "OpenCoreGraphics"
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "OpenCoreGraphicsTests",
            dependencies: [
                "OpenCoreGraphics",
                .target(name: "OpenCoreGraphicsGLTestBootstrap", condition: .when(platforms: [.macOS]))
            ],
            resources: [
                .copy("Resources")
            ]
        ),
    ]
)
