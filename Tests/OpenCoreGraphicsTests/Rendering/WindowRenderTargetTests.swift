import Foundation
import Testing
#if os(macOS)
import Darwin
#endif
@testable import OpenCoreGraphics

/// Tests command queuing and delegation for a window render target.
@MainActor
struct WindowRenderTargetTests {
    /// Exercises the legacy context bridge and its window backend on the main actor.
    @Test
    private func legacyContextExecutesWindowCommandsOnMainActor() {
        let renderer = RecordingRenderBackend()
        let target = WindowRenderTarget(size: CGSize(width: 8, height: 8), renderer: renderer)
        let context = CGContext(width: 8, height: 8)
        context.renderTarget = target
        let clip = CGRect(x: 1, y: 1, width: 4, height: 4)
        let rectangle = CGRect(x: 2, y: 2, width: 2, height: 2)

        context.clip(to: clip)
        context.setFillColor(.black)
        context.fill(rectangle)
        context.flush()

        #expect(renderer.commands == [
            .resetClip,
            .clipRect(clip),
            .fillPath(path: CGPath(rect: rectangle), rule: .winding, color: .black, blendMode: .normal)
        ])
        #expect(renderer.size == CGSize(width: 8, height: 8))
    }

    #if os(macOS) || os(Linux)
    /// Checks the legacy window target's runtime guard without sharing a mutable context.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_GL_COMPARISON"] != "1"))
    private func legacyWindowFlushRejectsOffActorExecution() async {
        #if os(macOS)
        let expectedExit = ExitTest.Condition.signal(SIGTRAP)
        #else
        let expectedExit = ExitTest.Condition.failure
        #endif
        let result = await #expect(processExitsWith: expectedExit, observing: [\.standardErrorContent]) {
            let target = await MainActor.run {
                let renderer = RecordingRenderBackend()
                return WindowRenderTarget(size: CGSize(width: 8, height: 8), renderer: renderer)
            }
            await Task.detached {
                FileHandle.standardError.write(Data("about to flush\n".utf8))
                target.flush()
            }.value
        }
        #expect(result.map { String(decoding: $0.standardErrorContent, as: UTF8.self) }
            .map { $0.contains("about to flush\n") } == true)
    }

    /// Checks that clipping also reaches the runtime guard before a window flush.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_GL_COMPARISON"] != "1"))
    private func legacyWindowClipRejectsOffActorExecution() async {
        #if os(macOS)
        let expectedExit = ExitTest.Condition.signal(SIGTRAP)
        #else
        let expectedExit = ExitTest.Condition.failure
        #endif
        let result = await #expect(processExitsWith: expectedExit, observing: [\.standardErrorContent]) {
            let target = await MainActor.run {
                let renderer = RecordingRenderBackend()
                return WindowRenderTarget(size: CGSize(width: 8, height: 8), renderer: renderer)
            }
            await Task.detached {
                FileHandle.standardError.write(Data("about to clip\n".utf8))
                target.setClipRegions([.rectangle(CGRect(x: 1, y: 1, width: 4, height: 4))])
            }.value
        }
        #expect(result.map { String(decoding: $0.standardErrorContent, as: UTF8.self) }
            .map { $0.contains("about to clip\n") } == true)
    }
    #endif

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

    /// Reports and retains a rendering failure through the public CGContext drawing path.
    @Test
    func publicContextFlushLogsAndKeepsRenderingFailureTerminal() throws {
        let renderer = RecordingRenderBackend()
        renderer.nextRenderingError = .texture(.allocationFailed)
        let target = WindowRenderTarget(size: CGSize(width: 32, height: 24), renderer: renderer)
        var reportedErrors: [GLRendererError] = []
        target.reportRenderingFailure = { reportedErrors.append($0) }
        let context = CGContext(width: 32, height: 24)
        context.renderTarget = target
        let fontURL = try #require(
            Bundle.module.url(forResource: "tiny-test", withExtension: "ttf", subdirectory: "Resources")
        )
        let font = try #require(CGFont(fontURL.path))
        let glyph = try #require(font.glyph(for: "I"))
        context.setFont(font)
        context.setFontSize(16)
        context.showGlyphs([glyph], at: [OpenCoreGraphics.CGPoint(x: 4, y: 18)])
        context.flush()

        #expect(reportedErrors == [.texture(.allocationFailed)])
        #expect(target.renderingError == .texture(.allocationFailed))
        #expect(renderer.commands.count == 1)

        context.fill(CGRect(x: 1, y: 1, width: 4, height: 4))
        context.flush()

        #expect(reportedErrors == [.texture(.allocationFailed)])
        #expect(target.renderingError == .texture(.allocationFailed))
        #expect(renderer.commands.count == 1)
        #expect(target.readPixels() == nil)
    }

    /// Rebases a resize prefix after failure and rejects later public drawing without replay.
    @Test
    func failedResizePrefixKeepsBarrierAndLaterCommandsConsistent() throws {
        let renderer = RecordingRenderBackend()
        renderer.nextRenderingError = .texture(.allocationFailed)
        let target = WindowRenderTarget(size: CGSize(width: 8, height: 8), renderer: renderer)
        var reportedErrors: [GLRendererError] = []
        target.reportRenderingFailure = { reportedErrors.append($0) }
        let command = try glyphCommandForFailure()
        target.submit(command)
        var viewportChanged = false
        target.enqueueFramebufferResize(CGSize(width: 12, height: 10)) {
            viewportChanged = true
        }

        #expect(target.renderingError == .texture(.allocationFailed))
        #expect(reportedErrors == [.texture(.allocationFailed)])
        #expect(renderer.commands == [command])
        #expect(viewportChanged == false)
        #expect(target.size == CGSize(width: 8, height: 8))

        let context = CGContext(width: 8, height: 8)
        context.renderTarget = target
        context.fill(CGRect(x: 1, y: 1, width: 2, height: 2))
        context.flush()
        var laterViewportChanged = false
        target.enqueueFramebufferResize(CGSize(width: 14, height: 12)) {
            laterViewportChanged = true
        }
        #expect(target.flushBeforeResize() == false)

        #expect(renderer.commands == [command])
        #expect(renderer.executionSizes == [CGSize(width: 8, height: 8)])
        #expect(reportedErrors == [.texture(.allocationFailed)])
        #expect(viewportChanged == false)
        #expect(laterViewportChanged == false)
        #expect(target.size == CGSize(width: 8, height: 8))
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

    /// Builds one glyph command that the recording backend uses to trigger an injected failure.
    private func glyphCommandForFailure() throws -> DrawCommand {
        let bitmap = CGGlyphBitmap(
            width: 1,
            height: 1,
            xOffset: 0,
            yOffset: 0,
            coverage: Data([255])
        )
        let atlas = try #require(CGGlyphAtlas(bitmaps: [bitmap]))
        return .glyphs(
            glyphs: [1],
            positions: [OpenCoreGraphics.CGPoint(x: 1, y: 2)],
            fontName: nil,
            fontSize: 12,
            glyphAtlas: atlas,
            characterSpacing: 0,
            textMatrix: .identity,
            textPosition: .zero,
            ctm: .identity,
            color: .black,
            blendMode: .normal
        )
    }

    /// Drains old-size work before resizing A even when B is the current context.
    @Test
    func resizesOwningContextAfterPendingCommands() throws {
        let contextA = try #require(OpaquePointer(bitPattern: 0xA))
        let contextB = try #require(OpaquePointer(bitPattern: 0xB))
        let state = RecordingContextDriverState(contextA: contextA, contextB: contextB)
        let selectorA = GLFWContextSelector.make(contextA, state.makeDriver())
        let selectorB = GLFWContextSelector.make(contextB, state.makeDriver())
        let renderer = RecordingContextRenderBackend(name: "A", contextState: state, pixels: [])
        let target = WindowRenderTarget(size: CGSize(width: 8, height: 8), renderer: renderer)
        target.contextSelector = selectorA
        let context = CGContext(width: 8, height: 8)
        context.renderTarget = target
        let clip = CGRect(x: 1, y: 1, width: 5, height: 5)
        context.clip(to: clip)
        context.fill(CGRect(x: 2, y: 2, width: 2, height: 2))
        #expect(selectorB.select() == nil)

        let success = GLFWFramebufferResize.apply(
            selectorA,
            12,
            10,
            {
                context.flush()
                return target.flushBeforeResize()
            },
            { width, height in state.record("viewport(\(width)x\(height))", owner: "A") },
            { width, height in
                target.updateSize(CGSize(width: width, height: height))
                context.resizeWindowContext(Int(width), Int(height))
            }
        )

        #expect(success)
        #expect(state.events == [
            "select:A", "execute:A@A", "select:B", "select:A",
            "select:A", "execute:A@A", "viewport(12x10):A@A", "select:A", "execute:A@A"
        ])
        #expect(renderer.executionSizes == [
            CGSize(width: 8, height: 8),
            CGSize(width: 8, height: 8),
            CGSize(width: 12, height: 10)
        ])
        #expect(renderer.commands.count == 5)
        #expect(Array(renderer.commands.suffix(2)) == [.resetClip, .clipRect(clip)])
        #expect(context.width == 12)
        #expect(context.height == 10)
        #expect(context.boundingBoxOfClipPath == clip)
    }

    /// Leaves the viewport, dimensions, and queued commands untouched on selection failure.
    @Test
    func doesNotResizeWhenContextSelectionFails() throws {
        let contextA = try #require(OpaquePointer(bitPattern: 0xA))
        let contextB = try #require(OpaquePointer(bitPattern: 0xB))
        let state = RecordingContextDriverState(contextA: contextA, contextB: contextB)
        let selectorA = GLFWContextSelector.make(contextA, state.makeDriver())
        let selectorB = GLFWContextSelector.make(contextB, state.makeDriver())
        let renderer = RecordingContextRenderBackend(name: "A", contextState: state, pixels: [])
        let target = WindowRenderTarget(size: CGSize(width: 8, height: 8), renderer: renderer)
        target.contextSelector = selectorA
        target.submit(.resetClip)
        #expect(selectorB.select() == nil)
        state.rejectsSelection = true
        var viewportChanged = false
        var stateChanged = false

        let success = GLFWFramebufferResize.apply(
            selectorA,
            12,
            10,
            { target.flushBeforeResize() },
            { _, _ in viewportChanged = true },
            { _, _ in stateChanged = true }
        )

        #expect(success == false)
        #expect(viewportChanged == false)
        #expect(stateChanged == false)
        #expect(target.size == CGSize(width: 8, height: 8))
        #expect(renderer.commands.isEmpty)
        state.rejectsSelection = false
        target.flush()
        #expect(renderer.commands == [.resetClip])
    }

    /// Keeps queued work at its old size if selection fails while draining the resize.
    @Test
    func doesNotResizeWhenDrainingPendingCommandsFails() throws {
        let contextA = try #require(OpaquePointer(bitPattern: 0xA))
        let contextB = try #require(OpaquePointer(bitPattern: 0xB))
        let state = RecordingContextDriverState(contextA: contextA, contextB: contextB)
        let selectorA = GLFWContextSelector.make(contextA, state.makeDriver())
        let selectorB = GLFWContextSelector.make(contextB, state.makeDriver())
        let renderer = RecordingContextRenderBackend(name: "A", contextState: state, pixels: [])
        let target = WindowRenderTarget(size: CGSize(width: 8, height: 8), renderer: renderer)
        target.contextSelector = selectorA
        let context = CGContext(width: 8, height: 8)
        context.renderTarget = target
        context.fill(CGRect(x: 1, y: 1, width: 2, height: 2))
        var viewportChanged = false
        var stateChanged = false

        let success = GLFWFramebufferResize.apply(
            selectorA,
            12,
            10,
            {
                #expect(selectorB.select() == nil)
                state.rejectsSelection = true
                context.flush()
                return target.flushBeforeResize()
            },
            { _, _ in viewportChanged = true },
            { _, _ in stateChanged = true }
        )

        #expect(success == false)
        #expect(viewportChanged == false)
        #expect(stateChanged == false)
        #expect(renderer.commands.isEmpty)
        #expect(context.width == 8)
        #expect(target.contextError == .selectionFailed)
        state.rejectsSelection = false
        target.flush()
        #expect(renderer.commands.count == 1)
        #expect(renderer.executionSizes == [CGSize(width: 8, height: 8)])
    }

    /// Retries one failed resize on readback without another callback and preserves command order.
    @Test
    func retriesFailedResizeOnReadbackWithoutAnotherCallback() throws {
        let contextA = try #require(OpaquePointer(bitPattern: 0xA))
        let contextB = try #require(OpaquePointer(bitPattern: 0xB))
        let state = RecordingContextDriverState(contextA: contextA, contextB: contextB)
        let selectorA = GLFWContextSelector.make(contextA, state.makeDriver())
        let selectorB = GLFWContextSelector.make(contextB, state.makeDriver())
        let renderer = RecordingContextRenderBackend(name: "A", contextState: state, pixels: [1, 2, 3, 4])
        let target = WindowRenderTarget(size: CGSize(width: 8, height: 8), renderer: renderer)
        target.contextSelector = selectorA
        let context = CGContext(width: 8, height: 8)
        context.renderTarget = target
        let clip = CGRect(x: 1, y: 1, width: 5, height: 5)
        context.clip(to: clip)
        context.fill(CGRect(x: 1, y: 1, width: 1, height: 1))
        #expect(selectorB.select() == nil)
        state.rejectsSelection = true
        context.flush()
        context.resizeWindowContext(12, 10)
        target.enqueueFramebufferResize(CGSize(width: 12, height: 10)) {
            state.record("viewport(12x10)", owner: "A")
        }
        #expect(target.contextError == .selectionFailed)
        #expect(target.size == CGSize(width: 8, height: 8))
        let laterClip = CGRect(x: 2, y: 2, width: 2, height: 2)
        context.clip(to: laterClip)
        context.fill(CGRect(x: 2, y: 2, width: 1, height: 1))
        context.flush()
        #expect(renderer.commands.count == 2)
        #expect(target.readPixels() == nil)
        #expect(state.events.contains("viewport(12x10):A@A") == false)

        state.rejectsSelection = false
        #expect(target.readPixels() == Data([1, 2, 3, 4]))

        #expect(target.contextError == nil)
        #expect(target.size == CGSize(width: 12, height: 10))
        #expect(context.width == 12)
        #expect(context.height == 10)
        #expect(renderer.executionSizes == [
            CGSize(width: 8, height: 8), CGSize(width: 8, height: 8),
            CGSize(width: 12, height: 10), CGSize(width: 12, height: 10)
        ])
        #expect(renderer.commands.count == 9)
        #expect(Array(renderer.commands[3..<5]) == [.resetClip, .clipRect(clip)])
        #expect(Array(renderer.commands[5..<8]) == [.resetClip, .clipRect(clip), .clipRect(laterClip)])
        let viewportIndex = try #require(state.events.firstIndex(of: "viewport(12x10):A@A"))
        #expect(state.events[viewportIndex - 1] == "execute:A@A")
        #expect(state.events[viewportIndex + 1] == "execute:A@A")
        #expect(state.events.last == "read:A@A")
    }

    /// Applies multiple failed events in order and ends at the newest physical dimensions.
    @Test
    func retriesMultipleResizeBarriersInCommandOrder() throws {
        let contextA = try #require(OpaquePointer(bitPattern: 0xA))
        let contextB = try #require(OpaquePointer(bitPattern: 0xB))
        let state = RecordingContextDriverState(contextA: contextA, contextB: contextB)
        let selector = GLFWContextSelector.make(contextA, state.makeDriver())
        let renderer = RecordingContextRenderBackend(name: "A", contextState: state, pixels: [])
        let target = WindowRenderTarget(size: CGSize(width: 8, height: 8), renderer: renderer)
        target.contextSelector = selector
        #expect(GLFWContextSelector.make(contextB, state.makeDriver()).select() == nil)
        state.rejectsSelection = true
        target.submit(.clipRect(CGRect(x: 1, y: 1, width: 1, height: 1)))
        target.enqueueFramebufferResize(CGSize(width: 12, height: 10)) {
            state.record("viewport1", owner: "A")
        }
        target.submit(.clipRect(CGRect(x: 2, y: 2, width: 2, height: 2)))
        target.enqueueFramebufferResize(CGSize(width: 16, height: 14)) {
            state.record("viewport2", owner: "A")
        }
        target.submit(.resetClip)

        state.rejectsSelection = false
        target.flush()

        #expect(target.size == CGSize(width: 16, height: 14))
        #expect(renderer.executionSizes == [
            CGSize(width: 8, height: 8),
            CGSize(width: 12, height: 10),
            CGSize(width: 16, height: 14)
        ])
        #expect(renderer.commands == [
            .clipRect(CGRect(x: 1, y: 1, width: 1, height: 1)),
            .clipRect(CGRect(x: 2, y: 2, width: 2, height: 2)),
            .resetClip
        ])
        let first = try #require(state.events.firstIndex(of: "viewport1:A@A"))
        let second = try #require(state.events.firstIndex(of: "viewport2:A@A"))
        #expect(first < second)
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
private final class RecordingRenderBackend: CGWindowRenderBackend, CGWindowRenderFailureReporting,
    CGPixelSurfaceRenderer {
    /// The commands received from the render target.
    private(set) var commands: [DrawCommand] = []

    /// The size received with the most recent render call.
    private(set) var size: OpenCoreGraphics.CGSize?

    /// The framebuffer dimensions used for each command batch.
    private(set) var executionSizes: [OpenCoreGraphics.CGSize] = []

    /// Pixel snapshots received for direct software-surface presentation.
    private(set) var surfaceSnapshots: [CGImageSnapshot] = []

    /// Destination sizes received for direct software-surface presentation.
    private(set) var surfaceSizes: [OpenCoreGraphics.CGSize] = []

    /// The failure to return for the next command batch containing glyphs.
    var nextRenderingError: GLRendererError?

    /// The failure produced by the most recently executed command batch.
    private(set) var renderingError: GLRendererError?

    /// Records a renderer invocation.
    /// - Parameters:
    ///   - commands: The drawing operations submitted for rendering.
    ///   - size: The render destination dimensions.
    func execute(_ commands: [DrawCommand], size: OpenCoreGraphics.CGSize) {
        self.commands.append(contentsOf: commands)
        self.size = size
        executionSizes.append(size)
        renderingError = nil
        if commands.contains(where: {
            if case .glyphs = $0 { return true }
            return false
        }) {
            renderingError = nextRenderingError
            nextRenderingError = nil
        }
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
private final class RecordingRenderBackendWithoutSurfaceSupport: CGWindowRenderBackend {
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
private final class RecordingContextRenderBackend: CGWindowRenderBackend, CGPixelSurfaceRenderer, CGPixelReadbackRenderer {
    /// The fixed window label assigned to this fake renderer.
    private let name: String

    /// The state used to observe which fake context is current during operations.
    private let contextState: RecordingContextDriverState

    /// The bytes returned by a fake framebuffer read.
    private let pixels: [UInt8]

    /// The ordered commands executed by this renderer.
    private(set) var commands: [DrawCommand] = []

    /// The framebuffer dimensions used for each executed command batch.
    private(set) var executionSizes: [OpenCoreGraphics.CGSize] = []

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
        executionSizes.append(size)
        contextState.record("execute", owner: name)
    }

    /// Records a software surface presentation.
    /// - Parameters:
    ///   - image: The surface's pixel snapshot.
    ///   - size: The destination dimensions.
    func renderSoftwareSurface(_ image: CGImageSnapshot, size: OpenCoreGraphics.CGSize) {
        presentationCount += 1
        contextState.record("present", owner: name)
    }

    /// Records a readback and returns this window's distinct pixel color.
    /// - Parameter size: The framebuffer dimensions.
    /// - Returns: The fake framebuffer's RGBA bytes.
    func readPixels(size: OpenCoreGraphics.CGSize) -> [UInt8]? {
        contextState.record("read", owner: name)
        return pixels
    }
}
