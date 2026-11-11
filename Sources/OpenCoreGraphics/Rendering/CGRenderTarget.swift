import Foundation

/// Receives backend-independent drawing commands and exposes rendered pixels.
protocol CGRenderTarget {
    /// The dimensions of the drawing destination in pixels.
    var size: CGSize { get }

    /// Adds a drawing command to the target.
    /// - Parameter command: The operation to submit for rendering.
    func submit(_ command: DrawCommand)

    /// Returns the target's current pixel data when it has rendered an image.
    /// - Returns: Pixel bytes, or nil when the target does not produce pixel data.
    func readPixels() -> Data?

    /// Replaces the coverage mask used to clip subsequent rendering.
    /// - Parameter mask: The current clip coverage, or nil to remove clipping.
    func setClipMask(_ mask: CoverageMask?)

    /// Replaces the ordered clip regions used by backends that apply clipping directly.
    /// - Parameter regions: The device-space regions that form the current clip.
    func setClipRegions(_ regions: [CGClipRegion])

    /// Completes rendering for the commands submitted since the previous flush.
    func flush()
}

extension CGRenderTarget {
    /// Does nothing for targets that do not support coverage clipping.
    /// - Parameter mask: The current clip coverage, or nil to remove clipping.
    func setClipMask(_ mask: CoverageMask?) { }

    /// Does nothing for targets that apply clipping through a coverage mask.
    /// - Parameter regions: The device-space regions that form the current clip.
    func setClipRegions(_ regions: [CGClipRegion]) { }

    /// Does nothing for targets that render each submitted command immediately.
    func flush() { }
}

/// Executes drawing commands for a destination of the supplied size.
protocol CGRenderBackend: AnyObject {
    /// Renders a sequence of commands into a destination.
    /// - Parameters:
    ///   - commands: The operations to render in order.
    ///   - size: The destination dimensions in pixels.
    func execute(_ commands: [DrawCommand], size: CGSize)
}

/// Executes window drawing commands on the main actor after selecting the owning GL context.
@MainActor
protocol CGWindowRenderBackend: AnyObject {
    /// Renders a sequence of commands into a window destination.
    /// - Parameters:
    ///   - commands: The operations to render in order.
    ///   - size: The destination dimensions in pixels.
    func execute(_ commands: [DrawCommand], size: CGSize)
}

/// Exposes a typed failure produced while executing commands for a window.
@MainActor
protocol CGWindowRenderFailureReporting: AnyObject {
    /// The failure from the most recent command batch, if execution did not complete.
    var renderingError: GLRendererError? { get }
}

/// Renders a software bitmap directly through a window's textured OpenGL pipeline.
@MainActor
protocol CGPixelSurfaceRenderer: AnyObject {
    /// Replaces the cached surface texture and draws it across the destination.
    /// - Parameters:
    ///   - image: The current immutable pixel snapshot.
    ///   - size: The destination dimensions in pixels.
    func renderSoftwareSurface(_ image: CGImageSnapshot, size: CGSize)
}

/// Reads rendered pixels from an OpenGL framebuffer.
@MainActor
protocol CGPixelReadbackRenderer: AnyObject {
    /// Copies the framebuffer into bottom-up RGBA bytes.
    /// - Parameter size: The framebuffer dimensions in pixels.
    /// - Returns: RGBA bytes, or nil when the dimensions cannot be read safely.
    func readPixels(size: CGSize) -> [UInt8]?
}

/// A test target that records submitted commands without rendering pixels.
final class RecordingRenderTarget: CGRenderTarget {
    /// The dimensions of this target in pixels.
    let size: CGSize

    /// The commands submitted to this target, in submission order.
    private(set) var commands: [DrawCommand] = []

    /// The ordered clip regions most recently assigned to this target.
    private(set) var clipRegions: [CGClipRegion] = []

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

    /// Stores the clip regions for later inspection.
    /// - Parameter regions: The device-space regions that form the current clip.
    func setClipRegions(_ regions: [CGClipRegion]) {
        clipRegions = regions
    }
}
