import Foundation

/// Receives backend-independent drawing commands and exposes rendered pixels.
@MainActor
protocol CGRenderTarget: Sendable {
    /// The dimensions of the drawing destination in pixels.
    var size: CGSize { get }

    /// Adds a drawing command to the target.
    /// - Parameter command: The operation to submit for rendering.
    func submit(_ command: DrawCommand)

    /// Returns the target's current pixel data when it has rendered an image.
    /// - Returns: Pixel bytes, or nil when the target does not produce pixel data.
    func readPixels() -> Data?

    /// Completes rendering for the commands submitted since the previous flush.
    func flush()
}

extension CGRenderTarget {
    /// Does nothing for targets that render each submitted command immediately.
    func flush() { }
}

/// Executes drawing commands for a destination of the supplied size.
@MainActor
protocol CGRenderBackend: AnyObject {
    /// Renders a sequence of commands into a destination.
    /// - Parameters:
    ///   - commands: The operations to render in order.
    ///   - size: The destination dimensions in pixels.
    func execute(_ commands: [DrawCommand], size: CGSize)
}

/// A test target that records submitted commands without rendering pixels.
final class RecordingRenderTarget: CGRenderTarget {
    /// The dimensions of this target in pixels.
    let size: CGSize

    /// The commands submitted to this target, in submission order.
    private(set) var commands: [DrawCommand] = []

    /// Creates a command-recording target.
    /// - Parameter size: The dimensions to associate with the target.
    init(size: CGSize) {
        self.size = size
    }

    /// Stores a command for later inspection.
    /// - Parameter command: The operation to append to the recording.
    func submit(_ command: DrawCommand) {
        commands.append(command)
    }

    /// Returns nil because this target does not execute rendering.
    /// - Returns: Always nil for a command-only recording target.
    func readPixels() -> Data? {
        nil
    }
}
