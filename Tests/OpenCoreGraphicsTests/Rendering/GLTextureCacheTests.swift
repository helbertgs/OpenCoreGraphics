import Foundation
import Testing
@testable import OpenCoreGraphics

@MainActor
struct GLTextureCacheTests {
    /// Verifies image texture formats depend on channel count, not color space.
    @Test
    func choosesTextureFormatFromChannelCount() {
        #expect(GLTexturePixelFormat.forChannelCount(1) == .red)
        #expect(GLTexturePixelFormat.forChannelCount(2) == .rgba)
        #expect(GLTexturePixelFormat.forChannelCount(3) == .rgb)
        #expect(GLTexturePixelFormat.forChannelCount(4) == .rgba)
        #expect(GLTexturePixelFormat.forChannelCount(5) == nil)
    }

    /// Verifies only `.none` selects nearest filtering.
    @Test
    func mapsInterpolationQualityToTextureFilter() {
        #expect(GLTextureFilter.forQuality(.none) == .nearest)
        #expect(GLTextureFilter.forQuality(.default) == .linear)
        #expect(GLTextureFilter.forQuality(.high) == .linear)
    }

    /// Verifies repeated requests for one image create only one texture.
    @Test
    func reusesTextureForSameImageIdentity() throws {
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        let image = makeImage()

        let first = try cache.texture(for: image)
        let second = try cache.texture(for: image)

        #expect(first === second)
        #expect(loader.loadCount == 1)
    }

    /// Verifies evicting an image causes its next request to create a new texture.
    @Test
    func evictionAllowsTextureToBeRecreated() throws {
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        let image = makeImage()
        let first = try cache.texture(for: image)

        cache.evict(image)
        let second = try cache.texture(for: image)

        #expect(first !== second)
        #expect(loader.loadCount == 2)
    }

    /// Verifies changed pixels update the existing texture instead of allocating another one.
    @Test
    func updatesTextureForStableImageIdentity() throws {
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        let identity = UUID()
        let firstImage = makeSnapshot(identity: identity, pixel: [1, 2, 3, 4])
        let updatedImage = makeSnapshot(identity: identity, pixel: [5, 6, 7, 8])

        let firstTexture = try cache.updateTexture(for: firstImage)
        let updatedTexture = try cache.updateTexture(for: updatedImage)

        #expect(firstTexture === updatedTexture)
        #expect(loader.loadCount == 1)
        #expect(loader.updateCount == 1)
        #expect(loader.updatedImageData == Data([5, 6, 7, 8]))
    }

    /// Verifies releasing a texture wrapper invokes its resource cleanup handler.
    @Test
    func releasesTextureIdentifierOnDeinitialization() {
        var releasedIdentifier: UInt32?
        var texture: GLTexture? = GLTexture(identifier: 42) {
            releasedIdentifier = $0
        }
        #expect(texture?.identifier == 42)

        texture = nil

        #expect(releasedIdentifier == 42)
    }

    /// Creates a small image backed by owned RGBA data for cache tests.
    private func makeImage() -> CGImage {
        CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: .sRGB,
            bitmapInfo: .byteOrder32Big,
            provider: CGDataProvider(data: Data([1, 2, 3, 4])),
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Creates a one-pixel snapshot with a caller-provided stable identity and color.
    /// - Parameters:
    ///   - identity: The identity associated with the cached texture.
    ///   - pixel: The RGBA bytes to store.
    /// - Returns: A complete one-pixel image snapshot.
    private func makeSnapshot(identity: UUID, pixel: [UInt8]) -> CGImageSnapshot {
        CGImageSnapshot(
            identity: identity,
            data: Data(pixel),
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            alphaInfo: .premultipliedLast,
            colorSpace: .sRGB,
            bitmapInfo: .byteOrder32Big
        )
    }
}

/// Records texture creation requests without requiring a current OpenGL context.
@MainActor
private final class RecordingGLTextureLoader: GLTextureLoader {
    /// The number of images passed to the fake loader.
    private(set) var loadCount = 0

    /// The number of updates applied to previously allocated textures.
    private(set) var updateCount = 0

    /// The pixel bytes from the most recent texture update.
    private(set) var updatedImageData: Data?

    /// Returns a fake texture identifier and records the image request.
    /// - Parameter image: The image requested from the loader.
    /// - Returns: A fake texture with no OpenGL release side effect.
    func makeTexture(from image: CGImageSnapshot) throws -> GLTexture {
        loadCount += 1
        return GLTexture(identifier: UInt32(loadCount), width: image.width, height: image.height, release: { _ in })
    }

    /// Records a content update without allocating a new fake texture.
    /// - Parameters:
    ///   - texture: The existing fake texture.
    ///   - image: The new pixel data.
    func updateTexture(_ texture: GLTexture, from image: CGImageSnapshot) throws {
        updateCount += 1
        updatedImageData = image.data
    }
}
