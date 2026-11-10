import Foundation
import Testing
@preconcurrency import OpenGLAD
import OpenGLFW
@testable import OpenCoreGraphics

/// Verifies image-cache updates and eviction against a real OpenGL framebuffer.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_GL_COMPARISON"] == "1"))
@MainActor
struct GLTextureCacheIntegrationTests {
    /// Confirms changed provider pixels update a live texture and budget eviction releases it.
    @Test
    func updatesAndEvictsRealTexturesWithoutChangingRenderedPixels() throws {
        let window: CGWindow
        do {
            window = try CGWindow(frame: CGRect(x: 0, y: 0, width: 16, height: 16), title: "Texture cache")
        } catch let error as CGWindowError {
            print("GL_RUNNER_GRAPHICS_UNAVAILABLE: \(error)")
            throw error
        }
        defer { window.destroy() }

        let windowReference = try #require(window.windowRef)
        let context = window.cgContext
        let renderer = try #require(Mirror(reflecting: window).descendant("renderer") as? GLRenderer)
        let cache = try #require(Mirror(reflecting: renderer).descendant("textureCache") as? GLTextureCache)
        cache.byteBudget = 8
        context.interpolationQuality = .none
        let viewport = OpenCoreGraphics.CGRect(
            x: 0,
            y: 0,
            width: Double(context.width),
            height: Double(context.height)
        )

        let mutableImage = makeImage(with: [255, 0, 0, 255])
        let provider = try #require(mutableImage.dataProvider)
        context.draw(mutableImage, in: viewport)
        context.flush()
        let originalPixel = try centerPixel(in: context)
        #expect(matches(originalPixel, red: true, green: false, blue: false))
        let originalIdentifier = try firstCachedTextureIdentifier(in: cache)
        #expect(glfwGetCurrentContext() == windowReference)
        #expect(glad_glIsTexture(originalIdentifier) == GL_TRUE)
        #expect(cache.retainedByteCount == 8)

        provider.data = Data([0, 0, 255, 255])
        context.draw(mutableImage, in: viewport)
        context.flush()
        let updatedPixel = try centerPixel(in: context)
        #expect(matches(updatedPixel, red: false, green: false, blue: true))
        let updatedIdentifier = try firstCachedTextureIdentifier(in: cache)
        #expect(updatedIdentifier == originalIdentifier)
        #expect(glad_glIsTexture(originalIdentifier) == GL_TRUE)
        #expect(cache.retainedByteCount == 8)

        let replacementImage = makeImage(with: [0, 255, 0, 255])
        context.draw(replacementImage, in: viewport)
        context.flush()
        let replacementPixel = try centerPixel(in: context)
        #expect(matches(replacementPixel, red: false, green: true, blue: false))
        let replacementIdentifier = try firstCachedTextureIdentifier(in: cache)
        #expect(replacementIdentifier != originalIdentifier)
        #expect(glad_glIsTexture(originalIdentifier) == GL_FALSE)
        #expect(glad_glIsTexture(replacementIdentifier) == GL_TRUE)
        #expect(cache.retainedByteCount == 8)
        #expect(glfwGetCurrentContext() == windowReference)

        print(
            "GL_TEXTURE_CACHE_REAL: updates=1 evictions=1 retainedBytes=\(cache.retainedByteCount) "
                + "budgetBytes=\(cache.byteBudget) updatedPixel=\(updatedPixel) "
                + "evictedPixel=\(replacementPixel) lifetime=verified"
        )
    }

    /// Creates a one-pixel opaque image backed by mutable provider storage.
    /// - Parameter pixels: The RGBA channels to expose through the image provider.
    /// - Returns: The image used by the real texture cache.
    private func makeImage(with pixels: [UInt8]) -> CGImage {
        CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: .sRGB,
            bitmapInfo: .byteOrder32Big,
            provider: CGDataProvider(data: Data(pixels)),
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Reads the bottom-up framebuffer pixel at its center.
    /// - Parameter context: The context whose framebuffer has been flushed.
    /// - Returns: The center pixel in RGBA byte order.
    private func centerPixel(in context: CGContext) throws -> [UInt8] {
        let pixels = try #require(context.renderTarget?.readPixels())
        let offset = (context.height / 2 * context.width + context.width / 2) * 4
        try #require(offset >= 0 && offset + 4 <= pixels.count)
        return Array(pixels[offset..<(offset + 4)])
    }

    /// Checks that one color channel dominates while the others remain near zero.
    /// - Parameters:
    ///   - pixel: The framebuffer's RGBA sample.
    ///   - red: Whether red should be the dominant channel.
    ///   - green: Whether green should be the dominant channel.
    ///   - blue: Whether blue should be the dominant channel.
    /// - Returns: Whether the pixel matches the requested opaque primary color.
    private func matches(_ pixel: [UInt8], red: Bool, green: Bool, blue: Bool) -> Bool {
        guard pixel.count == 4, pixel[3] > 245 else { return false }
        let channels = [pixel[0], pixel[1], pixel[2]]
        let expected = [red, green, blue]
        return zip(channels, expected).allSatisfy { value, isDominant in
            isDominant ? value > 245 : value < 10
        }
    }

    /// Finds the sole currently cached image texture.
    /// - Parameter cache: The renderer's image texture cache.
    /// - Returns: Its OpenGL identifier.
    private func firstCachedTextureIdentifier(in cache: GLTextureCache) throws -> UInt32 {
        let textures = try #require(
            Mirror(reflecting: cache).descendant("textures") as? [UUID: GLTexture]
        )
        return try #require(textures.values.first?.identifier)
    }
}
