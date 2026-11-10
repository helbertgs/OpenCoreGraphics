import Foundation

/// Creates OpenGL textures from immutable image data.
@MainActor
protocol GLTextureLoader {
    /// Loads an image into a newly owned texture.
    /// - Parameter image: The bitmap image whose bytes will be uploaded.
    /// - Returns: The texture that owns the uploaded OpenGL resource.
    /// - Throws: A `GLTextureError` when the image cannot be uploaded.
    func makeTexture(from image: CGImageSnapshot) throws -> GLTexture

    /// Replaces the pixel data of an existing texture without changing its identifier.
    /// - Parameters:
    ///   - texture: The texture whose image data should be replaced.
    ///   - image: The new bitmap contents.
    /// - Throws: A `GLTextureError` when the image cannot be uploaded.
    func updateTexture(_ texture: GLTexture, from image: CGImageSnapshot) throws
}

/// Reuses one OpenGL texture for each image object.
@MainActor
final class GLTextureCache {
    /// Creates textures when an image is first requested.
    private let loader: any GLTextureLoader

    /// Textures indexed by stable identity tokens from their source images.
    private var textures: [UUID: GLTexture] = [:]

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
        if let texture = textures[image.identity] {
            return texture
        }

        let texture = try loader.makeTexture(from: image)
        textures[image.identity] = texture
        return texture
    }

    /// Updates the cached texture for this image identity, creating it on first use.
    /// - Parameter image: The latest immutable pixel state for the image identity.
    /// - Returns: The texture associated with this image identity.
    /// - Throws: A `GLTextureError` when the image cannot be uploaded.
    func updateTexture(for image: CGImageSnapshot) throws -> GLTexture {
        if let texture = textures[image.identity] {
            try loader.updateTexture(texture, from: image)
            return texture
        }

        let texture = try loader.makeTexture(from: image)
        textures[image.identity] = texture
        return texture
    }

    /// Removes an image and its texture from the cache.
    /// - Parameter image: The image whose cached texture should be evicted.
    func evict(_ image: CGImage) {
        textures.removeValue(forKey: image.textureCacheIdentity)
    }
}
