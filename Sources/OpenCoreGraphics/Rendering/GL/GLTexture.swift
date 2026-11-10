@preconcurrency import OpenGLAD

/// Selects the texture filter that matches an interpolation quality.
enum GLTextureFilter: Equatable {
    /// Samples the nearest texel without smoothing.
    case nearest

    /// Interpolates between adjacent texels.
    case linear

    /// Maps the requested image interpolation quality to a texture filter.
    /// - Parameter quality: The image interpolation quality.
    /// - Returns: Nearest filtering for `.none`, and linear filtering otherwise.
    static func forQuality(_ quality: CGInterpolationQuality) -> GLTextureFilter {
        quality == .none ? .nearest : .linear
    }

    /// Returns the OpenGL constant for this filter.
    var openGLValue: GLint {
        switch self {
        case .nearest:
            GLint(GL_NEAREST)
        case .linear:
            GLint(GL_LINEAR)
        }
    }
}

/// Owns one OpenGL texture and releases it on the actor that owns its context.
@MainActor
final class GLTexture {
    /// The OpenGL identifier used when binding this texture.
    let identifier: UInt32

    /// The width of the currently allocated texture image.
    private(set) var width: Int

    /// The height of the currently allocated texture image.
    private(set) var height: Int

    /// The operation that releases the owned OpenGL identifier.
    private let release: @MainActor (UInt32) -> Void

    /// Creates a texture wrapper for an allocated OpenGL identifier.
    /// - Parameters:
    ///   - identifier: The OpenGL texture identifier.
    ///   - width: The width of the allocated texture image.
    ///   - height: The height of the allocated texture image.
    ///   - release: The operation to call when the wrapper is deallocated.
    init(
        identifier: UInt32,
        width: Int = 0,
        height: Int = 0,
        release: @escaping @MainActor (UInt32) -> Void = GLTexture.deleteTexture
    ) {
        self.identifier = identifier
        self.width = width
        self.height = height
        self.release = release
    }

    /// Records new storage dimensions after reallocating the OpenGL texture image.
    /// - Parameters:
    ///   - width: The updated texture width.
    ///   - height: The updated texture height.
    func updateDimensions(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Applies the context's image interpolation quality to this texture.
    /// - Parameter quality: The sampling quality requested by the drawing context.
    func setInterpolationQuality(_ quality: CGInterpolationQuality) {
        let filter = GLTextureFilter.forQuality(quality).openGLValue
        glad_glBindTexture(GLenum(GL_TEXTURE_2D), identifier)
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), filter)
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), filter)
    }

    /// Releases the texture while isolated to the main actor.
    isolated deinit {
        release(identifier)
    }

    /// Deletes an OpenGL texture identifier.
    private static func deleteTexture(_ identifier: UInt32) {
        var identifier = identifier
        glad_glDeleteTextures(1, &identifier)
    }
}
