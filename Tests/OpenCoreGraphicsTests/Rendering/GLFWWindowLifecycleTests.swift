import Foundation
import Testing
@preconcurrency import OpenGLAD
import OpenGLFW
@testable import OpenCoreGraphics

/// Observes the renderer without extending its lifetime.
private final class WeakGLRenderer {
    /// The observed renderer while it remains alive.
    weak var renderer: GLRenderer?

    /// Creates a weak reference to a renderer.
    /// - Parameter renderer: The renderer to observe.
    init(_ renderer: GLRenderer) {
        self.renderer = renderer
    }
}

/// Verifies GLFW window lifecycle when explicitly enabled on a machine with a display.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_GL_COMPARISON"] == "1"))
@MainActor
struct GLFWWindowLifecycleTests {
    /// Verifies destroying one window releases its renderer in its own context before destroying that context.
    @Test
    func destroysWindowResourcesInTheirOwningContextBeforeLaterContextRelease() throws {
        let windowA = try CGWindow(frame: CGRect(x: 0, y: 0, width: 32, height: 32), title: "Teardown A")
        var contextA: CGContext? = windowA.cgContext
        let windowB = try CGWindow(frame: CGRect(x: 0, y: 0, width: 32, height: 32), title: "Teardown B")
        defer {
            windowA.destroy()
            windowB.destroy()
        }

        let windowAReference = try #require(windowA.windowRef)
        let windowBReference = try #require(windowB.windowRef)
        let rendererReference = try #require(weakRenderer(of: windowA))
        #expect(rendererReference.renderer != nil)
        let program = try #require(programIdentifier(of: windowA))
        let framebufferCallback = try #require(glfwSetFramebufferSizeCallback(windowAReference, nil))
        glfwSetFramebufferSizeCallback(windowAReference, framebufferCallback)
        glfwMakeContextCurrent(windowAReference)
        #expect(glad_glIsProgram(program) == GL_TRUE)
        glfwMakeContextCurrent(windowBReference)
        let originalDestroyWindow = GLFWWindowTeardownRegistry.destroyWindow
        var observedWindowDestruction = false
        GLFWWindowTeardownRegistry.destroyWindow = { window in
            if window == windowAReference {
                observedWindowDestruction = true
                #expect(glfwGetCurrentContext() == windowAReference)
                #expect(rendererReference.renderer == nil)
                #expect(glad_glIsProgram(program) == GL_FALSE)
            }
            originalDestroyWindow(window)
        }
        defer { GLFWWindowTeardownRegistry.destroyWindow = originalDestroyWindow }
        #expect(glfwGetCurrentContext() == windowBReference)

        windowA.destroy()

        #expect(observedWindowDestruction)
        #expect(rendererReference.renderer == nil)
        #expect(windowA.windowRef == nil)
        #expect(glfwGetCurrentContext() == windowBReference)
        glad_glClearColor(0.125, 0.25, 0.5, 0.75)
        glad_glEnable(GLenum(GL_SCISSOR_TEST))
        windowA.clear()
        var clearColor = [GLfloat](repeating: 0, count: 4)
        clearColor.withUnsafeMutableBufferPointer { values in
            glad_glGetFloatv(GLenum(GL_COLOR_CLEAR_VALUE), values.baseAddress)
        }
        #expect(clearColor == [0.125, 0.25, 0.5, 0.75])
        #expect(glad_glIsEnabled(GLenum(GL_SCISSOR_TEST)) == GL_TRUE)
        glad_glDisable(GLenum(GL_SCISSOR_TEST))
        glad_glViewport(1, 2, 3, 4)
        let originalUserPointer = glfwGetWindowUserPointer(windowBReference)
        glfwSetWindowUserPointer(windowBReference, Unmanaged.passUnretained(windowA).toOpaque())
        framebufferCallback(windowBReference, 123, 456)
        glfwSetWindowUserPointer(windowBReference, originalUserPointer)
        var viewport = [GLint](repeating: 0, count: 4)
        viewport.withUnsafeMutableBufferPointer { values in
            glad_glGetIntegerv(GLenum(GL_VIEWPORT), values.baseAddress)
        }
        #expect(viewport == [1, 2, 3, 4])
        #expect(contextA?.width != 123)
        #expect(contextA?.height != 456)
        contextA?.flush()
        let targetA = try #require(contextA?.renderTarget as? WindowRenderTarget)
        #expect(targetA.contextError == .windowClosed)
        contextA = nil

        #expect(glfwGetCurrentContext() == windowBReference)
        #expect(windowAReference != windowBReference)
    }

    /// Reads distinct framebuffer colors after alternating draws and readbacks across two windows.
    @Test
    func selectsEachWindowContextForClearAndAlternatingReadback() throws {
        let windowA = try CGWindow(frame: CGRect(x: 0, y: 0, width: 8, height: 8), title: "Context A")
        let windowB = try CGWindow(frame: CGRect(x: 0, y: 0, width: 8, height: 8), title: "Context B")
        defer {
            windowA.destroy()
            windowB.destroy()
        }

        windowA.backgroundColor = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        windowB.backgroundColor = CGColor(red: 1, green: 1, blue: 0, alpha: 1)
        let contextA = windowA.cgContext
        let contextB = windowB.cgContext
        let targetA = try #require(contextA.renderTarget)
        let targetB = try #require(contextB.renderTarget)

        windowA.clear()
        windowB.clear()
        contextA.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        contextA.fill(CGRect(x: 2, y: 2, width: 4, height: 4))
        contextB.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        contextB.fill(CGRect(x: 2, y: 2, width: 4, height: 4))
        contextA.flush()
        contextB.flush()

        let pixelsA = try #require(targetA.readPixels())
        let pixelsB = try #require(targetB.readPixels())
        let pixelsAAgain = try #require(targetA.readPixels())
        let pixelsBAgain = try #require(targetB.readPixels())
        let centerPixelOffset = (4 * contextA.width + 4) * 4
        let centerPixelRange = centerPixelOffset..<(centerPixelOffset + 4)

        #expect(Array(pixelsA.prefix(4)) == [0, 0, 255, 255])
        #expect(Array(pixelsB.prefix(4)) == [255, 255, 0, 255])
        #expect(Array(pixelsA[centerPixelRange]) == [255, 0, 0, 255])
        #expect(Array(pixelsB[centerPixelRange]) == [0, 255, 0, 255])
        #expect(pixelsAAgain == pixelsA)
        #expect(pixelsBAgain == pixelsB)
    }

    /// Resizes A with B current without disturbing B's viewport, clip, or framebuffer.
    @Test
    func resizingOneWindowPreservesTheOtherWindowAndItsOwnClip() throws {
        let windowA = try CGWindow(frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Resize A")
        let windowB = try CGWindow(frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Resize B")
        defer {
            windowA.destroy()
            windowB.destroy()
        }
        let referenceA = try #require(windowA.windowRef)
        let referenceB = try #require(windowB.windowRef)
        let contextA = windowA.cgContext
        let contextB = windowB.cgContext
        let targetA = try #require(contextA.renderTarget)
        let targetB = try #require(contextB.renderTarget)
        let clipA = CGRect(x: 2, y: 2, width: 10, height: 10)
        let clipB = CGRect(x: 1, y: 1, width: 8, height: 8)
        windowA.backgroundColor = .black
        windowB.backgroundColor = .black
        windowA.clear()
        windowB.clear()
        contextA.clip(to: clipA)
        contextA.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        contextA.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        contextB.clip(to: clipB)
        contextB.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        contextB.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        contextB.flush()
        let pixelsBefore = try #require(targetB.readPixels())
        let bInside = (3 * contextB.width + 3) * 4
        let bOutside = (12 * contextB.width + 12) * 4
        #expect(Array(pixelsBefore[bInside..<(bInside + 4)]) == [0, 255, 0, 255])
        #expect(Array(pixelsBefore[bOutside..<(bOutside + 4)]) == [0, 0, 0, 255])
        var viewportBefore = [GLint](repeating: 0, count: 4)
        var scissorBefore = [GLint](repeating: 0, count: 4)
        viewportBefore.withUnsafeMutableBufferPointer { glad_glGetIntegerv(GLenum(GL_VIEWPORT), $0.baseAddress) }
        scissorBefore.withUnsafeMutableBufferPointer { glad_glGetIntegerv(GLenum(GL_SCISSOR_BOX), $0.baseAddress) }
        #expect(glad_glIsEnabled(GLenum(GL_SCISSOR_TEST)) == GL_TRUE)

        let callback = try #require(glfwSetFramebufferSizeCallback(referenceA, nil))
        glfwSetFramebufferSizeCallback(referenceA, callback)
        glfwSetWindowSize(referenceA, 24, 20)
        glfwPollEvents()
        var width: Int32 = 0
        var height: Int32 = 0
        glfwGetFramebufferSize(referenceA, &width, &height)
        try #require(width > 0 && height > 0)
        try #require(width != Int32(viewportBefore[2]) || height != Int32(viewportBefore[3]))
        glfwMakeContextCurrent(referenceB)
        callback(referenceA, width, height)
        #expect(glfwGetCurrentContext() == referenceA)
        #expect(contextA.width == Int(width))
        #expect(contextA.height == Int(height))
        #expect(targetA.size == CGSize(width: width, height: height))
        #expect(contextA.boundingBoxOfClipPath == clipA)

        glfwMakeContextCurrent(referenceB)
        var viewportAfter = [GLint](repeating: 0, count: 4)
        var scissorAfter = [GLint](repeating: 0, count: 4)
        viewportAfter.withUnsafeMutableBufferPointer { glad_glGetIntegerv(GLenum(GL_VIEWPORT), $0.baseAddress) }
        scissorAfter.withUnsafeMutableBufferPointer { glad_glGetIntegerv(GLenum(GL_SCISSOR_BOX), $0.baseAddress) }
        #expect(viewportAfter == viewportBefore)
        #expect(scissorAfter == scissorBefore)
        #expect(glad_glIsEnabled(GLenum(GL_SCISSOR_TEST)) == GL_TRUE)
        #expect(try #require(targetB.readPixels()) == pixelsBefore)

        contextA.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        contextA.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height)))
        contextA.flush()
        let pixelsA = try #require(targetA.readPixels())
        let inside = (3 * Int(width) + 3) * 4
        let outside = (15 * Int(width) + 15) * 4
        #expect(Array(pixelsA[inside..<(inside + 4)]) == [0, 0, 255, 255])
        #expect(Array(pixelsA[outside..<(outside + 4)]) != [0, 0, 255, 255])
        #expect(try #require(targetB.readPixels()) == pixelsBefore)

        contextB.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        contextB.fill(CGRect(x: 0, y: 0, width: Double(contextB.width), height: Double(contextB.height)))
        contextB.flush()
        let pixelsBAfterDrawing = try #require(targetB.readPixels())
        #expect(Array(pixelsBAfterDrawing[bInside..<(bInside + 4)]) == [255, 0, 0, 255])
        #expect(Array(pixelsBAfterDrawing[bOutside..<(bOutside + 4)]) == [0, 0, 0, 255])
    }

    /// Observes the private window renderer without retaining it during teardown.
    /// - Parameter window: The window owning the renderer.
    /// - Returns: A weak reference to its renderer, if one exists.
    private func weakRenderer(of window: CGWindow) -> WeakGLRenderer? {
        guard let renderer = Mirror(reflecting: window).descendant("renderer") as? GLRenderer else {
            return nil
        }
        return WeakGLRenderer(renderer)
    }

    /// Reads an owned program identifier without extending its renderer's lifetime.
    /// - Parameter window: The window owning the renderer.
    /// - Returns: The GL program identifier, if the renderer exists.
    private func programIdentifier(of window: CGWindow) -> UInt32? {
        guard let renderer = Mirror(reflecting: window).descendant("renderer") as? GLRenderer,
              let program = Mirror(reflecting: renderer).descendant("program") as? GLProgram else {
            return nil
        }
        return program.identifier
    }
}
