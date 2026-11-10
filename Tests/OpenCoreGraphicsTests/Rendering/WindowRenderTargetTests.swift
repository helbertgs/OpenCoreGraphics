import Foundation
import Testing
@testable import OpenCoreGraphics

/// Tests command queuing and delegation for a window render target.
@MainActor
struct WindowRenderTargetTests {
    /// Verifies commands are executed only when flushed and are not replayed.
    @Test
    func flushExecutesQueuedCommandsOnce() {
        let renderer = RecordingRenderBackend()
        let target = WindowRenderTarget(size: CGSize(width: 32, height: 24), renderer: renderer)
        let command = DrawCommand.fillPath(
            path: CGPath(rect: CGRect(x: 1, y: 2, width: 3, height: 4)),
            rule: .winding,
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            blendMode: .normal
        )

        target.submit(command)
        #expect(renderer.commands.isEmpty)

        target.flush()
        #expect(renderer.commands == [command])
        #expect(renderer.size == CGSize(width: 32, height: 24))

        target.updateSize(CGSize(width: 40, height: 48))
        target.submit(command)
        target.flush()
        #expect(renderer.commands == [command, command])
        #expect(renderer.size == CGSize(width: 40, height: 48))
    }

    /// Verifies a surface is presented after queued commands with stable texture identity and updated pixels.
    @Test
    func presentsSoftwareSurfaceAfterPendingCommands() throws {
        let renderer = RecordingRenderBackend()
        let target = WindowRenderTarget(size: CGSize(width: 2, height: 2), renderer: renderer)
        let surface = try #require(
            PixelSurface(
                data: nil,
                width: 2,
                height: 2,
                bytesPerRow: 8,
                colorSpace: .sRGB,
                alphaInfo: .premultipliedLast,
                bitmapInfo: .byteOrderDefault
            )
        )
        let command = DrawCommand.fillPath(
            path: CGPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1)),
            rule: .winding,
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            blendMode: .normal
        )
        #expect(surface.setPixel(.init(red: 10, green: 20, blue: 30, alpha: 255), x: 0, y: 0))
        #expect(surface.setPixel(.init(red: 40, green: 50, blue: 60, alpha: 255), x: 0, y: 1))

        target.submit(command)
        try target.presentSoftwareSurface(surface)
        let firstSnapshot = try #require(renderer.surfaceSnapshots.first)

        #expect(renderer.commands == [command])
        #expect(renderer.surfaceSizes == [CGSize(width: 2, height: 2)])
        #expect(firstSnapshot.data == Data([40, 50, 60, 255, 0, 0, 0, 0, 10, 20, 30, 255, 0, 0, 0, 0]))
        #expect(firstSnapshot.colorSpace == .sRGB)

        #expect(surface.setPixel(.init(red: 70, green: 80, blue: 90, alpha: 255), x: 0, y: 0))
        try target.presentSoftwareSurface(surface)
        let secondSnapshot = try #require(renderer.surfaceSnapshots.last)

        #expect(firstSnapshot.identity == secondSnapshot.identity)
        #expect(firstSnapshot.data != secondSnapshot.data)
        #expect(renderer.surfaceSizes.count == 2)
    }

    /// Verifies presenting a surface reports when its backend lacks texture support.
    @Test
    func rejectsSurfacePresentationForUnsupportedBackend() throws {
        let renderer = RecordingRenderBackendWithoutSurfaceSupport()
        let target = WindowRenderTarget(
            size: CGSize(width: 1, height: 1),
            renderer: renderer
        )
        let surface = try #require(
            PixelSurface(
                data: nil,
                width: 1,
                height: 1,
                bytesPerRow: 4,
                colorSpace: .sRGB,
                alphaInfo: .premultipliedLast,
                bitmapInfo: .byteOrderDefault
            )
        )

        #expect(throws: WindowRenderTargetError.unsupportedRenderer) {
            try target.presentSoftwareSurface(surface)
        }
    }
}

/// Records backend calls without requiring an OpenGL context.
private final class RecordingRenderBackend: CGRenderBackend, CGPixelSurfaceRenderer {
    /// The commands received from the render target.
    private(set) var commands: [DrawCommand] = []

    /// The size received with the most recent render call.
    private(set) var size: OpenCoreGraphics.CGSize?

    /// Pixel snapshots received for direct software-surface presentation.
    private(set) var surfaceSnapshots: [CGImageSnapshot] = []

    /// Destination sizes received for direct software-surface presentation.
    private(set) var surfaceSizes: [OpenCoreGraphics.CGSize] = []

    /// Records a renderer invocation.
    /// - Parameters:
    ///   - commands: The drawing operations submitted for rendering.
    ///   - size: The render destination dimensions.
    func execute(_ commands: [DrawCommand], size: OpenCoreGraphics.CGSize) {
        self.commands.append(contentsOf: commands)
        self.size = size
    }

    /// Records a software surface upload and presentation.
    /// - Parameters:
    ///   - image: The surface's pixel snapshot.
    ///   - size: The destination dimensions.
    func renderSoftwareSurface(_ image: CGImageSnapshot, size: OpenCoreGraphics.CGSize) {
        surfaceSnapshots.append(image)
        surfaceSizes.append(size)
    }
}

/// Backend that does not support direct pixel-surface presentation.
private final class RecordingRenderBackendWithoutSurfaceSupport: CGRenderBackend {
    /// Ignores commands because this backend is only used to verify capability errors.
    /// - Parameters:
    ///   - commands: The drawing operations submitted for rendering.
    ///   - size: The render destination dimensions.
    func execute(_ commands: [DrawCommand], size: OpenCoreGraphics.CGSize) { }
}
