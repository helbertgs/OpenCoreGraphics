import Foundation

/// A failure raised while presenting a software-rendered surface in a window.
enum WindowRenderTargetError: Error, Equatable {
    /// The window renderer has already been released.
    case rendererUnavailable

    /// The window owning the render target has been closed.
    case windowClosed

    /// The assigned backend does not support textured software-surface presentation.
    case unsupportedRenderer

    /// A valid surface failed to produce one of its in-bounds pixels.
    case invalidSurfacePixel

    /// The window's OpenGL context could not be selected for the requested operation.
    case contextSelectionFailed
}

/// A resize barrier positioned between commands submitted before and after a framebuffer event.
private struct PendingFramebufferResize {
    /// The number of queued commands that precede this resize.
    var precedingCommandCount: Int

    /// The new framebuffer dimensions.
    let size: CGSize

    /// The clip active at the instant the framebuffer changed.
    let clipRegions: [CGClipRegion]

    /// Updates the viewport after selecting the owning context.
    let updateViewport: @MainActor () -> Void
}

/// Queues window drawing commands for the main-actor OpenGL renderer.
@MainActor
final class WindowRenderTarget: CGRenderTarget {
    /// The pixel dimensions of the window render destination.
    private var windowSize: CGSize

    /// The renderer owned by the window, which may be released during teardown.
    private weak var renderer: (any CGRenderBackend)?

    /// The selector tracking whether the window that owns this target is still open.
    var contextSelector: GLFWContextSelector?

    /// The most recent context lifecycle failure observed by this target.
    private(set) var contextError: GLFWContextSelectionError?

    /// Commands accumulated until the context flushes its current frame.
    private var pendingCommands: [DrawCommand] = []

    /// Resize barriers awaiting execution in their original command order.
    private var pendingResizes: [PendingFramebufferResize] = []

    /// The ordered device-space regions that define the current window clip.
    private var clipRegions: [CGClipRegion] = []

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
        if clipRegions.isEmpty == false {
            enqueueClipRegions()
            _ = flushPendingCommands()
        }
    }

    /// Drains commands at the current size and reports whether resizing can proceed.
    var flushBeforeResize: @MainActor () -> Bool {
        { self.flushPendingCommands() }
    }

    /// Retries pending framebuffer changes without flushing ordinary queued work.
    var retryFramebufferResize: @MainActor () -> Bool {
        { self.pendingResizes.isEmpty || self.flushPendingCommands() }
    }

    /// Records a resize barrier and attempts it without discarding it on failure.
    var enqueueFramebufferResize: @MainActor (CGSize, @escaping @MainActor () -> Void) -> Void {
        { size, updateViewport in
            self.pendingResizes.append(
                PendingFramebufferResize(
                    precedingCommandCount: self.pendingCommands.count,
                    size: size,
                    clipRegions: self.clipRegions,
                    updateViewport: updateViewport
                )
            )
            _ = self.flushPendingCommands()
        }
    }

    /// Flushes pending commands, then displays the supplied software surface full-screen.
    /// - Parameter surface: The pixel storage produced by the software renderer.
    /// - Throws: `WindowRenderTargetError` when the backend cannot present the surface.
    func presentSoftwareSurface(_ surface: PixelSurface) throws {
        try ensureWindowIsOpen()
        guard let renderer else { throw WindowRenderTargetError.rendererUnavailable }
        guard let surfaceRenderer = renderer as? any CGPixelSurfaceRenderer else {
            throw WindowRenderTargetError.unsupportedRenderer
        }

        guard flushPendingCommands() else {
            throw contextOperationError
        }
        let image = try snapshot(from: surface)
        try selectWindowContext()
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
            if pendingResizes.isEmpty == false, flushPendingCommands() == false { return nil }
            do {
                try ensureWindowIsOpen()
                try selectWindowContext()
            } catch {
                return nil
            }
            guard let renderer = renderer as? any CGPixelReadbackRenderer else { return nil }
            guard let pixels = renderer.readPixels(size: windowSize) else { return nil }
            return Data(pixels)
        }
    }

    /// Renders all commands queued for the current frame.
    nonisolated func flush() {
        MainActor.assumeIsolated {
            _ = flushPendingCommands()
        }
    }

    /// Replaces the clip state used by the window's OpenGL renderer.
    /// - Parameter regions: The device-space regions that form the current clip.
    nonisolated func setClipRegions(_ regions: [CGClipRegion]) {
        MainActor.assumeIsolated {
            clipRegions = regions
            enqueueClipRegions()
            _ = flushPendingCommands()
        }
    }

    /// Appends a complete clip-state replacement after all previously queued operations.
    private func enqueueClipRegions() {
        pendingCommands.append(.resetClip)
        pendingCommands.append(contentsOf: clipRegions.map(\.drawCommand))
    }

    /// Rejects target operations after their owning window closes and records the typed failure.
    private func ensureWindowIsOpen() throws {
        if let error = contextSelector?.ensureOpen() {
            contextError = error
            throw WindowRenderTargetError.windowClosed
        }
    }

    /// Selects the owning window's context before issuing an operation to its renderer.
    private func selectWindowContext() throws {
        guard let contextSelector else {
            contextError = nil
            return
        }
        guard let error = contextSelector.select() else {
            contextError = nil
            return
        }
        contextError = error
        if error == .windowClosed {
            throw WindowRenderTargetError.windowClosed
        }
        throw WindowRenderTargetError.contextSelectionFailed
    }

    /// Executes pending clip and drawing work, preserving it if context selection fails.
    /// - Returns: Whether all currently pending work was executed or already complete.
    private func flushPendingCommands() -> Bool {
        guard (try? ensureWindowIsOpen()) != nil else {
            pendingCommands.removeAll(keepingCapacity: true)
            pendingResizes.removeAll(keepingCapacity: true)
            return false
        }
        guard let renderer else {
            return false
        }
        while let resize = pendingResizes.first {
            guard (try? selectWindowContext()) != nil else { return false }
            let count = resize.precedingCommandCount
            if count > 0 {
                renderer.execute(Array(pendingCommands.prefix(count)), size: windowSize)
                pendingCommands.removeFirst(count)
            }
            resize.updateViewport()
            windowSize = resize.size
            if resize.clipRegions.isEmpty == false {
                renderer.execute([.resetClip] + resize.clipRegions.map(\.drawCommand), size: windowSize)
            }
            pendingResizes.removeFirst()
            for index in pendingResizes.indices {
                pendingResizes[index].precedingCommandCount -= count
            }
        }
        guard pendingCommands.isEmpty == false else { return true }
        guard (try? selectWindowContext()) != nil else { return false }

        renderer.execute(pendingCommands, size: windowSize)
        pendingCommands.removeAll(keepingCapacity: true)
        return true
    }

    /// Returns the typed target error corresponding to the last failed context selection.
    private var contextOperationError: WindowRenderTargetError {
        switch contextError {
        case .windowClosed:
            .windowClosed
        case .selectionFailed:
            .contextSelectionFailed
        case nil:
            .rendererUnavailable
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
