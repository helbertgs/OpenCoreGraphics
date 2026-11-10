import Foundation

/// Queues window drawing commands for the main-actor OpenGL renderer.
@MainActor
final class WindowRenderTarget: CGRenderTarget {
    /// The pixel dimensions of the window render destination.
    var size: CGSize

    /// The renderer owned by the window, which may be released during teardown.
    private weak var renderer: (any CGRenderBackend)?

    /// Commands accumulated until the context flushes its current frame.
    private var pendingCommands: [DrawCommand] = []

    /// Creates a window target backed by its window's OpenGL renderer.
    /// - Parameters:
    ///   - size: The window dimensions in pixels.
    ///   - renderer: The OpenGL renderer owned by the window.
    init(size: CGSize, renderer: any CGRenderBackend) {
        self.size = size
        self.renderer = renderer
    }

    /// Adds a drawing command to the pending frame.
    /// - Parameter command: The operation to submit for rendering.
    func submit(_ command: DrawCommand) {
        pendingCommands.append(command)
    }

    /// Returns nil because the window target does not expose pixel readback yet.
    /// - Returns: Always nil for the window destination.
    func readPixels() -> Data? {
        nil
    }

    /// Renders all commands queued for the current frame.
    func flush() {
        guard let renderer else {
            pendingCommands.removeAll(keepingCapacity: true)
            return
        }

        renderer.execute(pendingCommands, size: size)
        pendingCommands.removeAll(keepingCapacity: true)
    }
}
