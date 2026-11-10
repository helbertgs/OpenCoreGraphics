import Foundation

/// Creates OpenGL textures from immutable image data.
@MainActor
protocol GLTextureLoader {
    /// Loads an image into a newly owned texture.
    /// - Parameter image: The bitmap image whose bytes will be uploaded.
    /// - Returns: The texture that owns the uploaded OpenGL resource.
    /// - Throws: A `GLTextureError` when the image cannot be uploaded.
    func makeTexture(from image: CGImageSnapshot) throws -> GLTexture

    /// Loads a glyph coverage atlas into a newly owned single-channel texture.
    /// - Parameter glyphAtlas: The packed 8-bit coverage pixels to upload.
    /// - Returns: The texture that owns the uploaded OpenGL resource.
    /// - Throws: A `GLTextureError` when the atlas dimensions or pixels are invalid.
    func makeTexture(from glyphAtlas: CGGlyphAtlas) throws -> GLTexture

    /// Replaces the pixel data of an existing texture without changing its identifier.
    /// - Parameters:
    ///   - texture: The texture whose image data should be replaced.
    ///   - image: The new bitmap contents.
    /// - Throws: A `GLTextureError` when the image cannot be uploaded.
    func updateTexture(_ texture: GLTexture, from image: CGImageSnapshot) throws
}

/// Reuses image textures under an LRU byte budget.
///
/// The budget counts estimated logical GPU level-zero bytes (8 bits per allocated
/// channel) plus retained snapshot data, not driver-chosen storage, padding,
/// temporary upload buffers, draw-command snapshots, or references held by callers.
/// Same-sized updates retain the original GPU format; resized textures use the new
/// upload format. Oversized images are returned uncached without displacing other
/// entries. Glyph atlases use a separate, short-lived path outside this budget.
///
/// Access, mutation and destruction must occur with the owning GL context current.
/// The renderer installs a batch flush before any texture mutation or eviction.
@MainActor
final class GLTextureCache {
    /// Creates textures when an image is first requested.
    private let loader: any GLTextureLoader

    /// Textures indexed by stable identity tokens from their source images.
    private var textures: [UUID: GLTexture] = [:]

    /// The last successfully uploaded immutable state for each image texture.
    private var uploadedImages: [UUID: CGImageSnapshot] = [:]

    /// Logical level-zero GPU bytes for each successfully allocated image texture.
    private var gpuBytes: [UUID: Int] = [:]

    /// Image identities ordered from least to most recently used.
    private var recency: [UUID] = []

    /// Maximum retained image bytes; reducing it immediately evicts older entries.
    var byteBudget = 64 * 1024 * 1024 {
        didSet { enforceBudget(newest: nil) }
    }

    /// Bytes retained by cached image textures and their last uploaded snapshots.
    private(set) var retainedByteCount = 0

    /// Flushes pending draws before changing or dropping a texture.
    var prepareForTextureMutation: @MainActor () -> Void = {}

    /// Textures indexed by stable identity tokens from their glyph atlases.
    private var glyphTextures: [UUID: GLTexture] = [:]

    /// Creates an empty cache with the specified texture loader.
    /// - Parameter loader: The implementation used to upload new textures.
    init(loader: any GLTextureLoader = OpenGLTextureLoader()) {
        self.loader = loader
    }

    /// Returns the cached texture or creates and caches one for the image.
    /// - Parameter image: The image whose texture is requested.
    /// - Returns: The texture associated with this exact image object.
    /// - Throws: A `GLTextureError` when the image cannot be uploaded.
    func texture(for image: CGImage) throws -> GLTexture {
        try texture(for: CGImageSnapshot(image: image))
    }

    /// Returns the cached texture or creates and caches one for the image snapshot.
    /// - Parameter image: The immutable image state captured by a draw command.
    /// - Returns: The texture associated with this image identity.
    /// - Throws: A `GLTextureError` when the image cannot be uploaded.
    func texture(for image: CGImageSnapshot) throws -> GLTexture {
        try updateTexture(for: image)
    }

    /// Returns the cached texture or creates one for a glyph coverage atlas.
    /// - Parameter glyphAtlas: The immutable coverage state captured by a draw command.
    /// - Returns: The texture associated with this atlas identity.
    /// - Throws: A `GLTextureError` when the atlas cannot be uploaded.
    func texture(for glyphAtlas: CGGlyphAtlas) throws -> GLTexture {
        if let texture = glyphTextures[glyphAtlas.identity] {
            return texture
        }

        let texture = try loader.makeTexture(from: glyphAtlas)
        glyphTextures[glyphAtlas.identity] = texture
        return texture
    }

    /// Updates changed cached content for this image identity, creating it on first use.
    /// - Parameter image: The latest immutable pixel state for the image identity.
    /// - Returns: The texture associated with this image identity.
    /// - Throws: A `GLTextureError` when the image cannot be uploaded.
    func updateTexture(for image: CGImageSnapshot) throws -> GLTexture {
        if let texture = textures[image.identity] {
            if uploadedImages[image.identity] != image {
                prepareForTextureMutation()
                try loader.updateTexture(texture, from: image)
                if uploadedImages[image.identity]?.width != image.width
                    || uploadedImages[image.identity]?.height != image.height {
                    gpuBytes[image.identity] = gpuByteCount(for: image)
                }
                uploadedImages[image.identity] = image
            }
            recency.removeAll { $0 == image.identity }
            recency.append(image.identity)
            enforceBudget(newest: image.identity)
            return texture
        }

        let texture = try loader.makeTexture(from: image)
        textures[image.identity] = texture
        uploadedImages[image.identity] = image
        gpuBytes[image.identity] = gpuByteCount(for: image)
        recency.append(image.identity)
        enforceBudget(newest: image.identity)
        return texture
    }

    /// Removes an image and its texture from the cache.
    /// - Parameter image: The image whose cached texture should be evicted.
    func evict(_ image: CGImage) {
        removeImage(identity: image.textureCacheIdentity)
    }

    /// Removes a glyph atlas and its texture from the cache.
    /// - Parameter glyphAtlas: The atlas whose cached texture should be evicted.
    func evict(_ glyphAtlas: CGGlyphAtlas) {
        if glyphTextures[glyphAtlas.identity] != nil {
            prepareForTextureMutation()
        }
        glyphTextures.removeValue(forKey: glyphAtlas.identity)
    }

    /// Estimates logical GPU bytes using the allocated upload format, with overflow saturation.
    private func gpuByteCount(for image: CGImageSnapshot) -> Int {
        guard image.width > 0, image.height > 0, image.bitsPerComponent == 8,
              image.bitsPerPixel > 0, image.bitsPerPixel.isMultiple(of: 8) else { return Int.max }
        let channels = image.bitsPerPixel / 8
        guard (1...4).contains(channels) else { return Int.max }
        let (pixels, pixelOverflow) = image.width.multipliedReportingOverflow(by: image.height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: channels == 2 ? 4 : channels)
        return pixelOverflow || byteOverflow ? Int.max : bytes
    }

    /// Recomputes retained bytes and evicts least-recently-used entries until within budget.
    private func enforceBudget(newest: UUID?) {
        if let newest {
            let (entryBytes, overflow) = (gpuBytes[newest] ?? 0)
                .addingReportingOverflow(uploadedImages[newest]?.data?.count ?? 0)
            if overflow || entryBytes > max(0, byteBudget) {
                removeImage(identity: newest)
            }
        }
        recountBytes()
        while retainedByteCount > max(0, byteBudget), let oldest = recency.first {
            removeImage(identity: oldest)
        }
    }

    /// Flushes pending draws and removes one cache-owned image and its accounting.
    private func removeImage(identity: UUID) {
        guard textures[identity] != nil else { return }
        prepareForTextureMutation()
        textures.removeValue(forKey: identity)
        uploadedImages.removeValue(forKey: identity)
        gpuBytes.removeValue(forKey: identity)
        recency.removeAll { $0 == identity }
        recountBytes()
    }

    /// Recomputes the logical image-cache footprint without overflowing.
    private func recountBytes() {
        retainedByteCount = 0
        for identity in recency {
            let (entryBytes, entryOverflow) = (gpuBytes[identity] ?? 0)
                .addingReportingOverflow(uploadedImages[identity]?.data?.count ?? 0)
            let (total, totalOverflow) = retainedByteCount.addingReportingOverflow(entryBytes)
            retainedByteCount = entryOverflow || totalOverflow ? Int.max : total
        }
    }
}
