import Foundation

/// Queues window drawing commands for the main-actor OpenGL renderer.
@MainActor
final class WindowRenderTarget: CGRenderTarget {
    /// The pixel dimensions of the window render destination.
    private var windowSize: CGSize

    /// The renderer owned by the window, which may be released during teardown.
    private weak var renderer: (any CGRenderBackend)?

    /// Commands accumulated until the context flushes its current frame.
    private var pendingCommands: [DrawCommand] = []

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

    /// Adds a drawing command to the pending frame.
    /// - Parameter command: The operation to submit for rendering.
    nonisolated func submit(_ command: DrawCommand) {
        MainActor.assumeIsolated {
            pendingCommands.append(command)
        }
    }

    /// Returns nil because the window target does not expose pixel readback yet.
    /// - Returns: Always nil for the window destination.
    nonisolated func readPixels() -> Data? {
        nil
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
}
