import Foundation
@preconcurrency import OpenGLAD

/// Uploads decoded image data to a temporary OpenGL texture.
@MainActor
enum GLImageTextureUpload {
    /// Uploads pixel data and generates mipmaps before releasing the temporary texture.
    /// - Parameters:
    ///   - data: The decoded pixel bytes.
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    ///   - channelCount: The number of channels in each pixel.
    static func upload(data: Data, width: Int32, height: Int32, channelCount: Int32) {
        let format = channelCount == 4 ? GLenum(GL_RGBA) : GLenum(GL_RGB)
        var texture: GLuint = 0
        glad_glGenTextures(1, &texture)
        defer { glad_glDeleteTextures(1, &texture) }
        glad_glBindTexture(GLenum(GL_TEXTURE_2D), texture)

        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLint(GL_REPEAT))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLint(GL_REPEAT))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLint(GL_LINEAR))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLint(GL_LINEAR))

        data.withUnsafeBytes { bytes in
            glad_glTexImage2D(
                GLenum(GL_TEXTURE_2D),
                0,
                GLint(format),
                GLsizei(width),
                GLsizei(height),
                0,
                format,
                GLenum(GL_UNSIGNED_BYTE),
                bytes.baseAddress
            )
        }

        glad_glGenerateMipmap(GLenum(GL_TEXTURE_2D))
    }
}
