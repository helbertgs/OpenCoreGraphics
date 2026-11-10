import Foundation
import Testing
@preconcurrency import OpenGLAD
import OpenGLFW
@testable import OpenCoreGraphics

/// Exercises failed window initialization through the real GLFW and OpenGL lifecycle.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_GL_COMPARISON"] == "1"))
@MainActor
struct GLWindowInitializationFailureTests {
    /// Confirms partial shader and buffer failures delete programs before window destruction.
    @Test(arguments: [false, true])
    func restoresOtherContextAfterPartialFailure(bufferFailure: Bool) throws {
        let other = try CGWindow(frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Existing")
        defer { other.destroy() }
        let otherContext = try #require(other.windowRef)
        let driver = GLInitializationFailureDriver(failCompilation: !bufferFailure)
        let originalFactory = CGWindow.rendererFactory
        let originalDestroy = GLFWWindowTeardownRegistry.destroyWindow
        var destroyed: [OpaquePointer] = []
        CGWindow.rendererFactory = {
            try GLRenderer(
                shaderCache: GLShaderCache(driver: driver),
                batchBufferDriver: GLInitializationFailingBufferDriver()
            )
        }
        GLFWWindowTeardownRegistry.destroyWindow = { window in
            #expect(window == driver.owner)
            #expect(glfwGetCurrentContext() == window)
            #expect(driver.deleted.count == (bufferFailure ? 4 : 2))
            #expect(driver.deleted.sorted() == driver.created.sorted())
            for identifier in driver.created {
                #expect(glad_glIsProgram(identifier) == GL_FALSE)
            }
            destroyed.append(window)
            originalDestroy(window)
        }
        defer {
            CGWindow.rendererFactory = originalFactory
            GLFWWindowTeardownRegistry.destroyWindow = originalDestroy
        }
        glfwMakeContextCurrent(otherContext)

        #expect(throws: (any Error).self) {
            try CGWindow(frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Failing")
        }

        #expect(driver.owner != nil)
        #expect(driver.owner != otherContext)
        #expect(driver.created.count == (bufferFailure ? 4 : 2))
        #expect(driver.deleted.count == driver.created.count)
        #expect(destroyed.count == 1)
        #expect(glfwGetCurrentContext() == otherContext)
        #expect(GLFWWindowTeardownRegistry.pending.isEmpty)
    }
}
