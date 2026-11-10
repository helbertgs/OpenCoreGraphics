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

    /// Verifies straight-alpha texture bytes are converted to premultiplied RGBA.
    @Test
    func premultipliesStraightAlphaForTextureUploads() throws {
        let snapshot = makeSnapshot(
            data: [200, 100, 50, 128],
            alphaInfo: .last,
            bitmapInfo: .byteOrder32Big
        )
        let prepared = try OpenGLTextureLoader().uploadData(for: snapshot)

        #expect(prepared.pixelFormat == .rgba)
        #expect(prepared.data == Data([100, 50, 25, 128]))
    }

    /// Verifies glyph coverage remains a tightly packed red-channel texture source.
    @Test
    func preparesGlyphAtlasForRedChannelUpload() throws {
        let atlas = try makeGlyphAtlas()
        let prepared = try OpenGLTextureLoader().uploadData(for: atlas)

        #expect(prepared.pixelFormat == .red)
        #expect(prepared.data == atlas.coverage)
        #expect(prepared.data.count == atlas.width * atlas.height)
    }

    /// Verifies sRGB image channels are converted to linear values before texture upload.
    @Test
    func convertsSRGBPixelsToLinearTextureChannels() throws {
        let snapshot = makeSnapshot(
            data: [128, 128, 128, 128],
            alphaInfo: .last,
            bitmapInfo: .byteOrder32Big,
            colorSpace: .sRGB
        )
        let prepared = try OpenGLTextureLoader().uploadData(for: snapshot)

        #expect(prepared.data == Data([28, 28, 28, 128]))
    }

    /// Verifies already-premultiplied pixels are preserved and alpha-first bytes become RGBA.
    @Test
    func preservesPremultipliedTextureBytesAndNormalizesAlphaFirst() throws {
        let premultiplied = makeSnapshot(
            data: [100, 50, 25, 128],
            alphaInfo: .premultipliedLast,
            bitmapInfo: .byteOrder32Big
        )
        let alphaFirst = makeSnapshot(
            data: [128, 200, 100, 50],
            alphaInfo: .first,
            bitmapInfo: .byteOrder32Big
        )

        #expect(try OpenGLTextureLoader().uploadData(for: premultiplied).data == Data([100, 50, 25, 128]))
        #expect(try OpenGLTextureLoader().uploadData(for: alphaFirst).data == Data([100, 50, 25, 128]))
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

    /// Verifies public provider mutations invalidate only when the captured bytes change.
    @Test
    private func detectsProviderDataMutationsAndReusesUnchangedUploads() throws {
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        let image = makeImage()
        let provider = try #require(image.dataProvider)
        let original = CGImageSnapshot(image: image)
        let texture = try cache.texture(for: original)

        provider.data = Data([1, 2, 3, 4])
        #expect(try cache.texture(for: image) === texture)
        provider.data?[0] = 9
        let changed = CGImageSnapshot(image: image)
        #expect(original.identity == changed.identity)
        #expect(original.data == Data([1, 2, 3, 4]))
        #expect(changed != original)
        #expect(try cache.texture(for: changed) === texture)
        #expect(try cache.texture(for: image) === texture)
        provider.data?.replaceSubrange(1..<3, with: [8, 7])
        #expect(try cache.texture(for: image) === texture)
        provider.data = Data([1, 2, 3, 4])
        #expect(try cache.texture(for: image) === texture)

        #expect(loader.loadCount == 1)
        #expect(loader.uploadedImages == [
            Data([1, 2, 3, 4]), Data([9, 2, 3, 4]),
            Data([9, 8, 7, 4]), Data([1, 2, 3, 4])
        ])
    }

    /// Verifies mutations through a no-copy external buffer are captured and uploaded.
    @Test
    private func detectsExternalStorageMutations() throws {
        let count = 4096
        let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        storage.initialize(repeating: 0, count: count)
        defer {
            storage.deinitialize(count: count)
            storage.deallocate()
        }
        let image = makeImage()
        let provider = try #require(image.dataProvider)
        provider.data = Data(bytesNoCopy: storage, count: count, deallocator: .none)
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        let before = CGImageSnapshot(image: image)
        let texture = try cache.texture(for: before)
        storage[0] = 255
        let after = CGImageSnapshot(image: image)

        #expect(before.identity == after.identity)
        #expect(before.data?.first == 0)
        #expect(after.data?.first == 255)
        #expect(try cache.texture(for: after) === texture)
        #expect(try cache.texture(for: image) === texture)
        #expect(loader.loadCount == 1)
        #expect(loader.updateCount == 1)
        #expect(loader.updatedImageData?.first == 255)
    }

    /// Verifies a failed upload leaves the last successful snapshot available for retry.
    @Test
    private func retriesFailedContentUpdate() throws {
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        let image = makeImage()
        let provider = try #require(image.dataProvider)
        let texture = try cache.texture(for: image)
        provider.data = nil
        loader.rejectMissingData = true
        #expect(throws: GLTextureError.missingPixelData) {
            try cache.texture(for: image)
        }
        provider.data = Data([1, 2, 3, 4])
        #expect(try cache.texture(for: image) === texture)
        #expect(loader.updateCount == 0)
        provider.data = Data([5, 6, 7, 8])
        #expect(try cache.texture(for: image) === texture)
        #expect(loader.loadCount == 1)
        #expect(loader.updateCount == 1)
        #expect(loader.updatedImageData == Data([5, 6, 7, 8]))
    }

    /// Verifies glyph atlas texture requests reuse and evict by atlas identity.
    @Test
    func reusesAndEvictsTextureForGlyphAtlas() throws {
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        let atlas = try makeGlyphAtlas()

        let first = try cache.texture(for: atlas)
        let second = try cache.texture(for: atlas)

        #expect(first === second)
        #expect(loader.loadCount == 1)

        cache.evict(atlas)
        let recreated = try cache.texture(for: atlas)

        #expect(recreated !== first)
        #expect(loader.loadCount == 2)
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

    /// Creates a small atlas containing one two-by-two glyph.
    /// - Returns: The packed coverage mask.
    private func makeGlyphAtlas() throws -> CGGlyphAtlas {
        let bitmap = CGGlyphBitmap(
            width: 2,
            height: 2,
            xOffset: 0,
            yOffset: 0,
            coverage: Data([0, 64, 128, 255])
        )
        return try #require(CGGlyphAtlas(bitmaps: [bitmap]))
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
            colorSpace: .genericRGBLinear,
            bitmapInfo: .byteOrder32Big
        )
    }

    /// Creates a one-pixel image snapshot with an explicit alpha and byte-order layout.
    /// - Parameters:
    ///   - data: The source pixel bytes.
    ///   - alphaInfo: The alpha layout associated with the bytes.
    ///   - bitmapInfo: The byte order associated with the bytes.
    ///   - colorSpace: The color space used to interpret the RGB channels.
    /// - Returns: A complete one-pixel image snapshot.
    private func makeSnapshot(
        data: [UInt8],
        alphaInfo: CGImageAlphaInfo,
        bitmapInfo: CGBitmapInfo,
        colorSpace: CGColorSpace = .genericRGBLinear
    ) -> CGImageSnapshot {
        CGImageSnapshot(
            identity: UUID(),
            data: Data(data),
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            alphaInfo: alphaInfo,
            colorSpace: colorSpace,
            bitmapInfo: bitmapInfo
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

    /// The bytes from each successful image creation or update, in upload order.
    private(set) var uploadedImages: [Data] = []

    /// Whether a missing image buffer causes the fake update to fail.
    var rejectMissingData = false

    /// Returns a fake texture identifier and records the image request.
    /// - Parameter image: The image requested from the loader.
    /// - Returns: A fake texture with no OpenGL release side effect.
    func makeTexture(from image: CGImageSnapshot) throws -> GLTexture {
        loadCount += 1
        if let data = image.data {
            uploadedImages.append(data)
        }
        return GLTexture(identifier: UInt32(loadCount), width: image.width, height: image.height, release: { _ in })
    }

    /// Returns a fake texture identifier and records the glyph atlas request.
    /// - Parameter glyphAtlas: The atlas requested from the loader.
    /// - Returns: A fake texture with no OpenGL release side effect.
    func makeTexture(from glyphAtlas: CGGlyphAtlas) throws -> GLTexture {
        loadCount += 1
        return GLTexture(
            identifier: UInt32(loadCount),
            width: glyphAtlas.width,
            height: glyphAtlas.height,
            release: { _ in }
        )
    }

    /// Records a content update without allocating a new fake texture.
    /// - Parameters:
    ///   - texture: The existing fake texture.
    ///   - image: The new pixel data.
    func updateTexture(_ texture: GLTexture, from image: CGImageSnapshot) throws {
        if rejectMissingData && image.data == nil {
            throw GLTextureError.missingPixelData
        }
        updateCount += 1
        updatedImageData = image.data
        if let data = image.data {
            uploadedImages.append(data)
        }
    }
}
