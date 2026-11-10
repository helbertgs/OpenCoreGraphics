/// Creates OpenGL textures from immutable image data.
@MainActor
protocol GLTextureLoader {
    /// Loads an image into a newly owned texture.
    /// - Parameter image: The bitmap image whose bytes will be uploaded.
    /// - Returns: The texture that owns the uploaded OpenGL resource.
    /// - Throws: A `GLTextureError` when the image cannot be uploaded.
    func makeTexture(from image: CGImage) throws -> GLTexture
}

/// Reuses one OpenGL texture for each image object.
@MainActor
final class GLTextureCache {
    /// Creates textures when an image is first requested.
    private let loader: any GLTextureLoader

    /// Retains image keys to prevent object-identifier reuse while cached.
    private var textures: [CGImage: GLTexture] = [:]

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
        if let texture = textures[image] {
            return texture
        }

        let texture = try loader.makeTexture(from: image)
        textures[image] = texture
        return texture
    }

    /// Removes an image and its texture from the cache.
    /// - Parameter image: The image whose cached texture should be evicted.
    func evict(_ image: CGImage) {
        textures.removeValue(forKey: image)
    }
}
