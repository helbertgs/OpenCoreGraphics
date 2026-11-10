import Foundation

/// A failure raised while presenting a software-rendered surface in a window.
enum WindowRenderTargetError: Error, Equatable {
    /// The window renderer has already been released.
    case rendererUnavailable

    /// The assigned backend does not support textured software-surface presentation.
    case unsupportedRenderer

    /// A valid surface failed to produce one of its in-bounds pixels.
    case invalidSurfacePixel
}

/// Queues window drawing commands for the main-actor OpenGL renderer.
@MainActor
final class WindowRenderTarget: CGRenderTarget {
    /// The pixel dimensions of the window render destination.
    private var windowSize: CGSize

    /// The renderer owned by the window, which may be released during teardown.
    private weak var renderer: (any CGRenderBackend)?

    /// Commands accumulated until the context flushes its current frame.
    private var pendingCommands: [DrawCommand] = []

    /// Stable identity used to update one cached texture as the surface changes.
    private let surfaceTextureIdentity = UUID()

    /// Creates a window target backed by its window's OpenGL renderer.
    /// - Parameters:
    ///   - size: The window dimensions in pixels.
    ///   - renderer: The OpenGL renderer owned by the window.
    init(size: CGSize, renderer: any CGRenderBackend) {
        windowSize = size
        self.renderer = renderer
    }

    /// Returns the window dimensions from the actor that owns the window.
    nonisolated var size: CGSize {
        MainActor.assumeIsolated { windowSize }
    }

    /// Updates the window dimensions after a framebuffer resize.
    /// - Parameter size: The new window dimensions in pixels.
    func updateSize(_ size: CGSize) {
        windowSize = size
    }

    /// Flushes pending commands, then displays the supplied software surface full-screen.
    /// - Parameter surface: The pixel storage produced by the software renderer.
    /// - Throws: `WindowRenderTargetError` when the backend cannot present the surface.
    func presentSoftwareSurface(_ surface: PixelSurface) throws {
        guard let renderer else { throw WindowRenderTargetError.rendererUnavailable }
        guard let surfaceRenderer = renderer as? any CGPixelSurfaceRenderer else {
            throw WindowRenderTargetError.unsupportedRenderer
        }

        flush()
        let image = try snapshot(from: surface)
        surfaceRenderer.renderSoftwareSurface(image, size: windowSize)
    }

    /// Adds a drawing command to the pending frame.
    /// - Parameter command: The operation to submit for rendering.
    nonisolated func submit(_ command: DrawCommand) {
        MainActor.assumeIsolated {
            pendingCommands.append(command)
        }
    }

    /// Reads the current framebuffer when its renderer supports pixel readback.
    /// - Returns: Bottom-up RGBA bytes, or nil when the renderer is unavailable.
    nonisolated func readPixels() -> Data? {
        MainActor.assumeIsolated {
            guard let renderer = renderer as? any CGPixelReadbackRenderer else { return nil }
            guard let pixels = renderer.readPixels(size: windowSize) else { return nil }
            return Data(pixels)
        }
    }

    /// Renders all commands queued for the current frame.
    nonisolated func flush() {
        MainActor.assumeIsolated {
            guard let renderer else {
                pendingCommands.removeAll(keepingCapacity: true)
                return
            }

            renderer.execute(pendingCommands, size: windowSize)
            pendingCommands.removeAll(keepingCapacity: true)
        }
    }

    /// Copies logical RGBA pixels into top-down rows for the textured-image shader.
    /// - Parameter surface: The software renderer's pixel storage.
    /// - Returns: A snapshot with a stable identity shared by later frames.
    /// - Throws: `WindowRenderTargetError.invalidSurfacePixel` if a surface coordinate is invalid.
    private func snapshot(from surface: PixelSurface) throws -> CGImageSnapshot {
        var imageData = Data(count: surface.width * surface.height * 4)
        try imageData.withUnsafeMutableBytes { storage in
            guard let bytes = storage.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw WindowRenderTargetError.invalidSurfacePixel
            }

            var offset = 0
            for y in (0..<surface.height).reversed() {
                for x in 0..<surface.width {
                    guard let pixel = surface.pixel(x: x, y: y) else {
                        throw WindowRenderTargetError.invalidSurfacePixel
                    }
                    bytes[offset] = pixel.red
                    bytes[offset + 1] = pixel.green
                    bytes[offset + 2] = pixel.blue
                    bytes[offset + 3] = pixel.alpha
                    offset += 4
                }
            }
        }

        return CGImageSnapshot(
            identity: surfaceTextureIdentity,
            data: imageData,
            width: surface.width,
            height: surface.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: surface.width * 4,
            alphaInfo: .premultipliedLast,
            colorSpace: surface.colorSpace,
            bitmapInfo: .byteOrder32Big
        )
    }
}
