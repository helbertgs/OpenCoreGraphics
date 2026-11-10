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

    /// Verifies LRU hits change eviction order and remaining textures release once at shutdown.
    @Test
    private func limitsRetainedBytesAndEvictsLeastRecentlyUsed() throws {
        let loader = RecordingGLTextureLoader()
        var cache: GLTextureCache? = GLTextureCache(loader: loader)
        cache?.byteBudget = 16
        let first = makeSnapshot(identity: UUID(), pixel: [1, 2, 3, 4])
        let second = makeSnapshot(identity: UUID(), pixel: [5, 6, 7, 8])
        let third = makeSnapshot(identity: UUID(), pixel: [9, 10, 11, 12])
        _ = try cache?.texture(for: first)
        _ = try cache?.texture(for: second)
        #expect(cache?.retainedByteCount == 16)
        _ = try cache?.texture(for: first)
        _ = try cache?.texture(for: third)
        #expect(loader.loadCount == 3)
        #expect(loader.releasedIdentifiers == [2])
        #expect(cache?.retainedByteCount == 16)
        _ = try cache?.texture(for: first)
        #expect(loader.loadCount == 3)
        cache = nil
        #expect(loader.releasedIdentifiers.sorted() == [1, 2, 3])
    }

    /// Verifies oversized entries bypass the cache without displacing smaller entries.
    @Test
    private func oversizedImageIsTransient() throws {
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        cache.byteBudget = 8
        let small = makeSnapshot(identity: UUID(), pixel: [1, 2, 3, 4])
        let large = makeSnapshot(identity: UUID(), pixel: [1, 2, 3, 4, 5])
        _ = try cache.texture(for: small)
        var transient: GLTexture? = try cache.texture(for: large)
        #expect(cache.retainedByteCount == 8)
        #expect(loader.releasedIdentifiers.isEmpty)
        transient = nil
        #expect(transient == nil)
        #expect(loader.releasedIdentifiers == [2])
        _ = try cache.texture(for: small)
        _ = try cache.texture(for: large)
        #expect(loader.loadCount == 3)
        #expect(loader.releasedIdentifiers == [2, 3])
    }

    /// Verifies reducing the budget immediately evicts older entries.
    @Test
    private func reducingBudgetTrimsImmediately() throws {
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        let first = makeSnapshot(identity: UUID(), pixel: [1, 2, 3, 4])
        let second = makeSnapshot(identity: UUID(), pixel: [5, 6, 7, 8])
        _ = try cache.texture(for: first)
        _ = try cache.texture(for: second)
        cache.byteBudget = 8
        #expect(cache.retainedByteCount == 8)
        #expect(loader.releasedIdentifiers == [1])
        cache.byteBudget = 0
        #expect(cache.retainedByteCount == 0)
        #expect(loader.releasedIdentifiers == [1, 2])
    }

    /// Verifies update and creation failures do not discard or reaccount successful entries.
    @Test
    private func failuresPreserveAccountingAndSuccessfulUpdateCanBecomeOversized() throws {
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        cache.byteBudget = 8
        let identity = UUID()
        let original = makeSnapshot(identity: identity, pixel: [1, 2, 3, 4])
        let expanded = makeSnapshot(identity: identity, pixel: [5, 6, 7, 8, 9])
        _ = try cache.texture(for: original)
        loader.rejectUpdates = true
        #expect(throws: GLTextureError.missingPixelData) {
            try cache.texture(for: expanded)
        }
        #expect(cache.retainedByteCount == 8)
        loader.rejectUpdates = false
        loader.rejectCreation = true
        #expect(throws: GLTextureError.allocationFailed) {
            try cache.texture(for: makeSnapshot(identity: UUID(), pixel: [1, 1, 1, 1]))
        }
        #expect(cache.retainedByteCount == 8)
        #expect(loader.releasedIdentifiers.isEmpty)
        _ = try cache.texture(for: expanded)
        #expect(cache.retainedByteCount == 0)
        #expect(loader.releasedIdentifiers == [1])
        loader.rejectCreation = false
        _ = try cache.texture(for: original)
        #expect(loader.loadCount == 2)
    }

    /// Verifies GPU format and retained source bytes are counted across updates and resize.
    @Test
    private func accountsForFormatsAndResizedSnapshots() throws {
        let loader = RecordingGLTextureLoader()
        let cache = GLTextureCache(loader: loader)
        let identity = UUID()
        let gray = makeSnapshot(identity: identity, width: 1, channels: 1, data: [1, 0, 0])
        let rgba = makeSnapshot(identity: identity, width: 1, channels: 4, data: [1, 2, 3, 4])
        let resized = makeSnapshot(identity: identity, width: 2, channels: 2, data: [1, 2, 3, 4, 0])
        _ = try cache.texture(for: gray)
        #expect(cache.retainedByteCount == 4)
        _ = try cache.texture(for: rgba)
        #expect(cache.retainedByteCount == 5)
        _ = try cache.texture(for: resized)
        #expect(cache.retainedByteCount == 13)
        #expect(loader.loadCount == 1)
        #expect(loader.updateCount == 2)
    }

    /// Verifies eviction flushes the actual pending batch before releasing its texture.
    @Test
    private func flushesPendingBatchBeforeEviction() throws {
        let loader = RecordingGLTextureLoader()
        let driver = TextureCacheBatchDriver()
        let batch = try GLBatchBuffer(driver: driver)
        let cache = GLTextureCache(loader: loader)
        cache.byteBudget = 8
        cache.prepareForTextureMutation = { batch.flush() }
        loader.onRelease = { identifier in
            driver.events.append("release \(identifier)")
        }
        let first = makeSnapshot(identity: UUID(), pixel: [1, 2, 3, 4])
        let second = makeSnapshot(identity: UUID(), pixel: [5, 6, 7, 8])
        _ = try cache.texture(for: first)
        let state = GLBatchState(program: 7, texture: 1, blendMode: .normal)
        try batch.append(vertices: [1, 2, 3, 4, 5, 6, 7, 8], state: state)
        _ = try cache.texture(for: second)
        #expect(driver.events == ["upload", "draw 1", "release 1"])
        #expect(driver.uploadedVertices == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(driver.drawnState == state)
        let nextState = GLBatchState(program: 8, texture: 2, blendMode: .multiply)
        try batch.append(vertices: [9, 10, 11, 12], state: nextState)
        batch.flush()
        #expect(driver.events == ["upload", "draw 1", "release 1", "upload", "draw 2"])
        #expect(driver.uploadedVertices == [9, 10, 11, 12])
        #expect(driver.drawnState == nextState)
    }

    /// Verifies a pending draw completes before its texture contents are updated.
    @Test
    private func flushesPendingBatchBeforeUpdate() throws {
        let loader = RecordingGLTextureLoader()
        let driver = TextureCacheBatchDriver()
        let batch = try GLBatchBuffer(driver: driver)
        let cache = GLTextureCache(loader: loader)
        cache.prepareForTextureMutation = { batch.flush() }
        loader.onUpdate = { driver.events.append("update") }
        let identity = UUID()
        _ = try cache.texture(for: makeSnapshot(identity: identity, pixel: [1, 2, 3, 4]))
        let state = GLBatchState(program: 7, texture: 1, blendMode: .normal)
        try batch.append(vertices: [1, 2, 3, 4], state: state)
        _ = try cache.texture(for: makeSnapshot(identity: identity, pixel: [5, 6, 7, 8]))
        #expect(driver.events == ["upload", "draw 1", "update"])
        #expect(driver.uploadedVertices == [1, 2, 3, 4])
        #expect(driver.drawnState == state)
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

    /// Creates a snapshot with explicit dimensions, format and retained source bytes.
    private func makeSnapshot(identity: UUID, width: Int, channels: Int, data: [UInt8]) -> CGImageSnapshot {
        CGImageSnapshot(
            identity: identity,
            data: Data(data),
            width: width,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: channels * 8,
            bytesPerRow: width * channels,
            alphaInfo: .none,
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

    /// Whether new texture allocation should fail.
    var rejectCreation = false

    /// Whether updates should fail before changing the texture.
    var rejectUpdates = false

    /// Identifiers released by fake texture wrappers.
    private(set) var releasedIdentifiers: [UInt32] = []

    /// Observes resource releases in relation to fake batch operations.
    var onRelease: @MainActor (UInt32) -> Void = { _ in }

    /// Observes successful updates in relation to fake batch operations.
    var onUpdate: @MainActor () -> Void = {}

    /// Returns a fake texture identifier and records the image request.
    /// - Parameter image: The image requested from the loader.
    /// - Returns: A fake texture with no OpenGL release side effect.
    func makeTexture(from image: CGImageSnapshot) throws -> GLTexture {
        if rejectCreation { throw GLTextureError.allocationFailed }
        loadCount += 1
        if let data = image.data {
            uploadedImages.append(data)
        }
        return GLTexture(identifier: UInt32(loadCount), width: image.width, height: image.height) { identifier in
            self.releasedIdentifiers.append(identifier)
            self.onRelease(identifier)
        }
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
        if rejectUpdates || (rejectMissingData && image.data == nil) {
            throw GLTextureError.missingPixelData
        }
        onUpdate()
        updateCount += 1
        updatedImageData = image.data
        if let data = image.data {
            uploadedImages.append(data)
        }
    }
}
