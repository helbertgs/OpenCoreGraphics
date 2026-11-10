@preconcurrency import OpenGLAD

/// Owns one OpenGL texture and releases it on the actor that owns its context.
@MainActor
final class GLTexture {
    /// The OpenGL identifier used when binding this texture.
    let identifier: UInt32

    /// The operation that releases the owned OpenGL identifier.
    private let release: @MainActor (UInt32) -> Void

    /// Creates a texture wrapper for an allocated OpenGL identifier.
    /// - Parameters:
    ///   - identifier: The OpenGL texture identifier.
    ///   - release: The operation to call when the wrapper is deallocated.
    init(identifier: UInt32, release: @escaping @MainActor (UInt32) -> Void = GLTexture.deleteTexture) {
        self.identifier = identifier
        self.release = release
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
