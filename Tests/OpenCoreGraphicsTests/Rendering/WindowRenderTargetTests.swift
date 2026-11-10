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
}

/// Records backend calls without requiring an OpenGL context.
private final class RecordingRenderBackend: CGRenderBackend {
    /// The commands received from the render target.
    private(set) var commands: [DrawCommand] = []

    /// The size received with the most recent render call.
    private(set) var size: CGSize?

    /// Records a renderer invocation.
    /// - Parameters:
    ///   - commands: The drawing operations submitted for rendering.
    ///   - size: The render destination dimensions.
    func execute(_ commands: [DrawCommand], size: CGSize) {
        self.commands.append(contentsOf: commands)
        self.size = size
    }
}
