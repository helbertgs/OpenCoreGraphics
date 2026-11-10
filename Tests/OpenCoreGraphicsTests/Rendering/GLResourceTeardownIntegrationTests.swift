import Foundation
import Testing
@preconcurrency import OpenGLAD
import OpenGLFW
@testable import OpenCoreGraphics

/// Validates resource destruction with real OpenGL independently of comparison-runner suites.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_GL_COMPARISON"] == "1"))
@MainActor
struct GLResourceTeardownIntegrationTests {
    /// Verifies budget eviction selects the owning context even when another window was current.
    @Test
    private func evictsImageInOwningContext() throws {
        let owner = try CGWindow(frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Cache owner")
        let other = try CGWindow(frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Other context")
        defer {
            owner.destroy()
            other.destroy()
        }
        let ownerRef = try #require(owner.windowRef)
        let otherRef = try #require(other.windowRef)
        do {
            let renderer = try #require(Mirror(reflecting: owner).descendant("renderer") as? GLRenderer)
            let cache = try #require(Mirror(reflecting: renderer).descendant("textureCache") as? GLTextureCache)
            cache.byteBudget = 8
            let first = CGImage(
                width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                space: .sRGB, bitmapInfo: .byteOrder32Big,
                provider: CGDataProvider(data: Data([255, 0, 0, 255])),
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )
            let second = CGImage(
                width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                space: .sRGB, bitmapInfo: .byteOrder32Big,
                provider: CGDataProvider(data: Data([0, 255, 0, 255])),
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )
            owner.cgContext.draw(first, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            owner.cgContext.flush()
            glfwMakeContextCurrent(ownerRef)
            let firstID: UInt32 = try {
                let textures = try #require(Mirror(reflecting: cache).descendant("textures") as? [UUID: GLTexture])
                return try #require(textures.values.first?.identifier)
            }()
            #expect(glad_glIsTexture(firstID) == GL_TRUE)
            glfwMakeContextCurrent(otherRef)
            owner.cgContext.draw(second, in: CGRect(x: 8, y: 0, width: 8, height: 8))
            owner.cgContext.flush()
            #expect(glfwGetCurrentContext() == ownerRef)
            glfwMakeContextCurrent(ownerRef)
            #expect(glad_glIsTexture(firstID) == GL_FALSE)
            #expect(cache.retainedByteCount == 8)
        }
    }

    /// Releases an implicitly deallocated window while another window's context is current.
    @Test
    func deallocationDestroysWindowInItsOwningContext() throws {
        var owner: CGWindow? = try CGWindow(
            frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Deallocated owner"
        )
        let ownerReference = try #require(owner?.windowRef)
        let other = try CGWindow(
            frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Remaining window"
        )
        defer { other.destroy() }
        let otherReference = try #require(other.windowRef)
        let originalDestroy = GLFWWindowTeardownRegistry.destroyWindow
        var destroyedOwner = 0
        GLFWWindowTeardownRegistry.destroyWindow = { window in
            if window == ownerReference {
                #expect(glfwGetCurrentContext() == ownerReference)
                destroyedOwner += 1
            }
            originalDestroy(window)
        }
        defer { GLFWWindowTeardownRegistry.destroyWindow = originalDestroy }

        glfwMakeContextCurrent(otherReference)
        owner = nil
        #expect(destroyedOwner == 1)
        #expect(glfwGetCurrentContext() == otherReference)
    }

    /// Destroys both windows in either order and observes their actual GL objects.
    @Test(arguments: [false, true])
    func deletesOwnedObjectsBeforeDestroyingEitherWindow(reverse: Bool) throws {
        let a = try CGWindow(frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Resource A")
        let b = try CGWindow(frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Resource B")
        defer {
            a.destroy()
            b.destroy()
        }
        let refA = try #require(a.windowRef)
        let refB = try #require(b.windowRef)
        let image = CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: .sRGB, bitmapInfo: .byteOrder32Big,
            provider: CGDataProvider(data: Data([255, 0, 0, 255])),
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
        for window in [a, b] {
            window.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            window.cgContext.flush()
        }
        let objectsA = try identifiers(of: a)
        let objectsB = try identifiers(of: b)
        let first = reverse ? b : a
        let second = reverse ? a : b
        let firstRef = reverse ? refB : refA
        let secondRef = reverse ? refA : refB
        glfwMakeContextCurrent(secondRef)

        let originalDestroy = GLFWWindowTeardownRegistry.destroyWindow
        var destroyed: [OpaquePointer] = []
        GLFWWindowTeardownRegistry.destroyWindow = { window in
            let objects = window == refA ? objectsA : objectsB
            #expect(glfwGetCurrentContext() == window)
            #expect(glad_glIsBuffer(objects.buffer) == GL_FALSE)
            #expect(glad_glIsVertexArray(objects.array) == GL_FALSE)
            #expect(glad_glIsTexture(objects.texture) == GL_FALSE)
            for program in objects.programs {
                #expect(glad_glIsProgram(program) == GL_FALSE)
            }
            destroyed.append(window)
            originalDestroy(window)
        }
        defer { GLFWWindowTeardownRegistry.destroyWindow = originalDestroy }

        first.destroy()
        first.destroy()
        #expect(glfwGetCurrentContext() == secondRef)
        #expect(destroyed == [firstRef])
        first.cgContext.flush()
        #expect(glfwGetCurrentContext() == secondRef)
        second.destroy()
        second.destroy()
        #expect(destroyed == [firstRef, secondRef])
    }

    /// Finds object identifiers without retaining their owning renderer during destruction.
    private func identifiers(of window: CGWindow) throws -> (
        buffer: UInt32, array: UInt32, texture: UInt32, programs: [UInt32]
    ) {
        let reference: OpaquePointer = try #require(window.windowRef)
        glfwMakeContextCurrent(reference)
        let renderer = try #require(Mirror(reflecting: window).descendant("renderer") as? GLRenderer)
        let mirror = Mirror(reflecting: renderer)
        let batch = try #require(mirror.descendant("batchBuffer") as? GLBatchBuffer)
        let batchMirror = Mirror(reflecting: batch)
        let buffer = try #require(batchMirror.descendant("vertexBuffer") as? UInt32)
        let array = try #require(batchMirror.descendant("vertexArray") as? UInt32)
        let cache = try #require(mirror.descendant("textureCache") as? GLTextureCache)
        let textures = try #require(Mirror(reflecting: cache).descendant("textures") as? [UUID: GLTexture])
        let texture = try #require(textures.values.first?.identifier)
        let programs = try ["program", "imageProgram", "gradientProgram", "textProgram"].map {
            try #require((mirror.descendant($0) as? GLProgram)?.identifier)
        }
        #expect(glad_glIsBuffer(buffer) == GL_TRUE)
        #expect(glad_glIsVertexArray(array) == GL_TRUE)
        #expect(glad_glIsTexture(texture) == GL_TRUE)
        return (buffer, array, texture, programs)
    }
}
