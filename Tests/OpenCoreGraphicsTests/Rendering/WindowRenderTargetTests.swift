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

    /// Verifies clip changes execute after pending drawing and reset the previous clip.
    @Test
    func appliesAndResetsClipRegions() {
        let renderer = RecordingRenderBackend()
        let target = WindowRenderTarget(size: CGSize(width: 32, height: 24), renderer: renderer)
        let rectangle = CGRect(x: 2, y: 3, width: 10, height: 12)
        let draw = DrawCommand.fillPath(
            path: CGPath(rect: rectangle),
            rule: .winding,
            color: .black,
            blendMode: .normal
        )

        target.submit(draw)
        target.flush()
        target.setClipRegions([.rectangle(rectangle)])
        target.setClipRegions([])

        #expect(renderer.commands == [
            draw,
            .resetClip,
            .clipRect(rectangle),
            .resetClip
        ])
    }

    /// Reapplies the active clip at the new size after it was already synchronized.
    @Test
    func reappliesClipRegionsAfterResize() {
        let renderer = RecordingRenderBackend()
        let target = WindowRenderTarget(size: CGSize(width: 32, height: 24), renderer: renderer)
        let rectangle = CGRect(x: 2, y: 3, width: 10, height: 12)

        target.setClipRegions([.rectangle(rectangle)])
        target.updateSize(CGSize(width: 64, height: 48))

        #expect(renderer.commands == [
            .resetClip,
            .clipRect(rectangle),
            .resetClip,
            .clipRect(rectangle)
        ])
        #expect(renderer.size == CGSize(width: 64, height: 48))
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

    /// Selects each owning context before rendering, presenting, or reading its pixels.
    @Test
    func selectsEachOwningContextForWindowOperations() throws {
        let contextA = try #require(OpaquePointer(bitPattern: 0xA))
        let contextB = try #require(OpaquePointer(bitPattern: 0xB))
        let contextState = RecordingContextDriverState(contextA: contextA, contextB: contextB)
        let driver = contextState.makeDriver()
        let rendererA = RecordingContextRenderBackend(
            name: "A",
            contextState: contextState,
            pixels: [255, 0, 0, 255]
        )
        let rendererB = RecordingContextRenderBackend(
            name: "B",
            contextState: contextState,
            pixels: [0, 255, 0, 255]
        )
        let targetA = WindowRenderTarget(size: CGSize(width: 1, height: 1), renderer: rendererA)
        let targetB = WindowRenderTarget(size: CGSize(width: 1, height: 1), renderer: rendererB)
        targetA.contextSelector = GLFWContextSelector.make(contextA, driver)
        targetB.contextSelector = GLFWContextSelector.make(contextB, driver)
        let firstCommand = DrawCommand.resetClip
        let secondCommand = DrawCommand.clipRect(CGRect(x: 1, y: 1, width: 2, height: 2))
        let commandForB = DrawCommand.clipRect(CGRect(x: 4, y: 4, width: 3, height: 3))
        targetA.submit(firstCommand)
        targetA.submit(secondCommand)
        targetB.submit(commandForB)

        targetA.flush()
        targetB.flush()
        #expect(targetA.readPixels() == Data([255, 0, 0, 255]))
        #expect(targetB.readPixels() == Data([0, 255, 0, 255]))

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
        try targetA.presentSoftwareSurface(surface)
        try targetB.presentSoftwareSurface(surface)

        #expect(rendererA.commands == [firstCommand, secondCommand])
        #expect(rendererB.commands == [commandForB])
        #expect(contextState.events == [
            "select:A",
            "execute:A@A",
            "select:B",
            "execute:B@B",
            "select:A",
            "read:A@A",
            "select:B",
            "read:B@B",
            "select:A",
            "present:A@A",
            "select:B",
            "present:B@B"
        ])
    }

    /// Retains queued work and reports selection errors instead of invoking the wrong context.
    @Test
    func preservesCommandsAndReportsContextSelectionFailure() throws {
        let context = try #require(OpaquePointer(bitPattern: 0xA))
        let otherContext = try #require(OpaquePointer(bitPattern: 0xB))
        let contextState = RecordingContextDriverState(contextA: context, contextB: otherContext)
        contextState.rejectsSelection = true
        let renderer = RecordingContextRenderBackend(
            name: "A",
            contextState: contextState,
            pixels: [255, 0, 0, 255]
        )
        let target = WindowRenderTarget(size: CGSize(width: 1, height: 1), renderer: renderer)
        target.contextSelector = GLFWContextSelector.make(context, contextState.makeDriver())
        let command = DrawCommand.resetClip
        target.submit(command)

        target.flush()

        #expect(renderer.commands.isEmpty)
        #expect(target.contextError == .selectionFailed)
        #expect(contextState.events == ["failure:selectionFailed"])

        contextState.rejectsSelection = false
        target.flush()

        #expect(renderer.commands == [command])
        #expect(target.contextError == nil)
        #expect(contextState.events == [
            "failure:selectionFailed",
            "select:A",
            "execute:A@A"
        ])

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
        let otherSelector = GLFWContextSelector.make(otherContext, contextState.makeDriver())
        #expect(otherSelector.select() == nil)
        contextState.rejectsSelection = true

        #expect(throws: WindowRenderTargetError.contextSelectionFailed) {
            try target.presentSoftwareSurface(surface)
        }
        #expect(renderer.presentationCount == 0)
        #expect(target.contextError == .selectionFailed)
    }

    /// Keeps drawing and clip operations in submission order across repeated selection failures.
    @Test
    func preservesCommandAndClipOrderAcrossSelectionFailures() throws {
        let contextA = try #require(OpaquePointer(bitPattern: 0xA))
        let contextB = try #require(OpaquePointer(bitPattern: 0xB))
        let contextState = RecordingContextDriverState(contextA: contextA, contextB: contextB)
        contextState.rejectsSelection = true
        let renderer = RecordingContextRenderBackend(
            name: "A",
            contextState: contextState,
            pixels: [0, 0, 0, 255]
        )
        let target = WindowRenderTarget(size: CGSize(width: 8, height: 8), renderer: renderer)
        target.contextSelector = GLFWContextSelector.make(contextA, contextState.makeDriver())
        let originalDraw = DrawCommand.clipRect(CGRect(x: 0, y: 0, width: 1, height: 1))
        let firstClip = CGRect(x: 1, y: 1, width: 2, height: 2)
        let laterDraw = DrawCommand.clipRect(CGRect(x: 2, y: 2, width: 3, height: 3))
        let latestClip = CGRect(x: 3, y: 3, width: 4, height: 4)

        target.submit(originalDraw)
        target.flush()
        target.setClipRegions([.rectangle(firstClip)])
        target.submit(laterDraw)
        target.setClipRegions([.rectangle(latestClip)])

        #expect(renderer.commands.isEmpty)
        #expect(contextState.events == [
            "failure:selectionFailed",
            "failure:selectionFailed",
            "failure:selectionFailed"
        ])

        contextState.rejectsSelection = false
        target.flush()

        #expect(renderer.commands == [
            originalDraw,
            .resetClip,
            .clipRect(firstClip),
            laterDraw,
            .resetClip,
            .clipRect(latestClip)
        ])
        #expect(contextState.events == [
            "failure:selectionFailed",
            "failure:selectionFailed",
            "failure:selectionFailed",
            "select:A",
            "execute:A@A"
        ])
    }

    /// Reports an unavailable renderer directly when presenting after its weak owner releases it.
    @Test
    func reportsUnavailableRendererWhenPresentingSurface() throws {
        var renderer: RecordingRenderBackend? = RecordingRenderBackend()
        let target = WindowRenderTarget(size: CGSize(width: 1, height: 1), renderer: try #require(renderer))
        renderer = nil
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

        #expect(throws: WindowRenderTargetError.rendererUnavailable) {
            try target.presentSoftwareSurface(surface)
        }
        #expect(target.contextError == nil)
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

    /// Verifies a window-owned target refuses rendering after its GLFW window closes.
    @Test
    func doesNotFlushAfterOwningWindowCloses() throws {
        let context = try #require(OpaquePointer(bitPattern: 0xE))
        var failures: [GLFWContextSelectionError] = []
        let driver = GLFWContextDriver.injecting(
            { context },
            { _ in },
            { failures.append($0) }
        )
        let selector = GLFWContextSelector.make(context, driver)
        let renderer = RecordingRenderBackend()
        let target = WindowRenderTarget(size: CGSize(width: 32, height: 24), renderer: renderer)
        let command = DrawCommand.fillPath(
            path: CGPath(rect: CGRect(x: 0, y: 0, width: 4, height: 4)),
            rule: .winding,
            color: .black,
            blendMode: .normal
        )
        target.contextSelector = selector
        target.submit(command)

        selector.close()
        target.flush()

        #expect(renderer.commands.isEmpty)
        #expect(target.contextError == .windowClosed)
        #expect(failures == [.windowClosed])
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

/// Stores selected contexts and the ordered operations performed by target tests.
@MainActor
private final class RecordingContextDriverState {
    /// Maps each fake window context to its stable test label.
    private let contextLabels: [OpaquePointer: String]

    /// The fake context currently selected by the driver.
    private var currentContext: OpaquePointer?

    /// The ordered context-selection and renderer-operation log.
    private(set) var events: [String] = []

    /// When true, leaves the current context unchanged when selection is attempted.
    var rejectsSelection = false

    /// Creates a recording state for two fake window contexts.
    /// - Parameters:
    ///   - contextA: The fake context representing window A.
    ///   - contextB: The fake context representing window B.
    init(contextA: OpaquePointer, contextB: OpaquePointer) {
        contextLabels = [contextA: "A", contextB: "B"]
    }

    /// Creates a fake context driver backed by this recording state.
    /// - Returns: A driver that records context selection and failures.
    func makeDriver() -> GLFWContextDriver {
        GLFWContextDriver.injecting(
            { self.currentContext },
            { context in
                guard self.rejectsSelection else {
                    self.currentContext = context
                    self.events.append("select:\(self.label(for: context))")
                    return
                }
            },
            { error in self.events.append("failure:\(error)") }
        )
    }

    /// Appends a renderer operation and the context that was current for it.
    /// - Parameters:
    ///   - operation: The name of the renderer operation.
    ///   - owner: The window expected to own the current context.
    func record(_ operation: String, owner: String) {
        events.append("\(operation):\(owner)@\(label(for: currentContext))")
    }

    /// Returns the stable label for a fake context.
    /// - Parameter context: The context to label.
    /// - Returns: Its test label, or `none`/`unknown` when it is not mapped.
    private func label(for context: OpaquePointer?) -> String {
        guard let context else { return "none" }
        return contextLabels[context] ?? "unknown"
    }
}

/// Records window-renderer calls together with the fake current context.
private final class RecordingContextRenderBackend: CGRenderBackend, CGPixelSurfaceRenderer, CGPixelReadbackRenderer {
    /// The fixed window label assigned to this fake renderer.
    private let name: String

    /// The state used to observe which fake context is current during operations.
    private let contextState: RecordingContextDriverState

    /// The bytes returned by a fake framebuffer read.
    private let pixels: [UInt8]

    /// The ordered commands executed by this renderer.
    private(set) var commands: [DrawCommand] = []

    /// The number of software surfaces presented by this renderer.
    private(set) var presentationCount = 0

    /// Creates a backend that records operations and returns deterministic pixels.
    /// - Parameters:
    ///   - name: The window label owning the renderer.
    ///   - contextState: The driver state used to record the current context.
    ///   - pixels: The RGBA bytes to return from readback.
    init(name: String, contextState: RecordingContextDriverState, pixels: [UInt8]) {
        self.name = name
        self.contextState = contextState
        self.pixels = pixels
    }

    /// Records a command batch without changing its order.
    /// - Parameters:
    ///   - commands: The drawing operations submitted for rendering.
    ///   - size: The render destination dimensions.
    func execute(_ commands: [DrawCommand], size: OpenCoreGraphics.CGSize) {
        self.commands.append(contentsOf: commands)
        let contextState = self.contextState
        let name = self.name
        MainActor.assumeIsolated {
            contextState.record("execute", owner: name)
        }
    }

    /// Records a software surface presentation.
    /// - Parameters:
    ///   - image: The surface's pixel snapshot.
    ///   - size: The destination dimensions.
    func renderSoftwareSurface(_ image: CGImageSnapshot, size: OpenCoreGraphics.CGSize) {
        presentationCount += 1
        let contextState = self.contextState
        let name = self.name
        MainActor.assumeIsolated {
            contextState.record("present", owner: name)
        }
    }

    /// Records a readback and returns this window's distinct pixel color.
    /// - Parameter size: The framebuffer dimensions.
    /// - Returns: The fake framebuffer's RGBA bytes.
    func readPixels(size: OpenCoreGraphics.CGSize) -> [UInt8]? {
        let contextState = self.contextState
        let name = self.name
        MainActor.assumeIsolated {
            contextState.record("read", owner: name)
        }
        return pixels
    }
}
