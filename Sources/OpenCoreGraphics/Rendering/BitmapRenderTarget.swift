import Foundation

/// Connects a bitmap context's pixel surface to the software renderer.
final class BitmapRenderTarget: CGRenderTarget {
    /// The dimensions of the bitmap in pixels.
    let size: CGSize

    /// The renderer that writes directly into the context's surface.
    private let renderer: SoftwareRenderer

    /// Commands waiting to be rendered into the bitmap.
    private var pendingCommands: [DrawCommand] = []

    /// Creates a bitmap target for an existing pixel surface.
    /// - Parameters:
    ///   - size: The dimensions of the bitmap in pixels.
    ///   - surface: The context-owned or caller-owned pixel storage.
    init(size: CGSize, surface: PixelSurface) {
        self.size = size
        renderer = SoftwareRenderer(surface: surface)
    }

    /// Queues a drawing command for the next flush.
    /// - Parameter command: The operation to render.
    func submit(_ command: DrawCommand) {
        pendingCommands.append(command)
    }

    /// Returns a copy of the current bitmap pixels.
    /// - Returns: Pixel bytes including row padding.
    func readPixels() -> Data? {
        renderer.readPixels()
    }

    /// Updates the mask used by subsequent bitmap rendering.
    /// - Parameter mask: The current clip coverage, or nil to remove clipping.
    func setClipMask(_ mask: CoverageMask?) {
        renderer.setClipMask(mask)
    }

    /// Renders and removes the commands accumulated for this bitmap.
    func flush() {
        renderer.execute(pendingCommands, size: size)
        pendingCommands.removeAll(keepingCapacity: true)
    }
}
