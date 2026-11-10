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
