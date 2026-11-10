import Foundation
@preconcurrency import OpenGLAD

/// A failure raised while converting an image into an OpenGL texture.
enum GLTextureError: Error, Equatable {
    /// The image has no pixel data to upload.
    case missingPixelData

    /// The dimensions, component size, or row layout are invalid.
    case invalidBitmapLayout

    /// The bitmap's component count is not supported.
    case unsupportedChannelCount(Int)

    /// OpenGL did not allocate a texture identifier.
    case allocationFailed
}

/// An OpenGL pixel format selected from the image's component count.
enum GLTexturePixelFormat: Equatable {
    /// One grayscale channel sampled from the red component.
    case red

    /// Three color channels in RGB order.
    case rgb

    /// Four color channels in RGBA order.
    case rgba

    /// Selects the format that matches the image's channel count.
    /// - Parameter channelCount: The number of 8-bit components in each source pixel.
    /// - Returns: The upload format, or nil when the component count is unsupported.
    static func forChannelCount(_ channelCount: Int) -> GLTexturePixelFormat? {
        switch channelCount {
        case 1:
            return .red
        case 2, 4:
            return .rgba
        case 3:
            return .rgb
        default:
            return nil
        }
    }

    /// Returns the OpenGL constant for this pixel format.
    var openGLValue: GLenum {
        switch self {
        case .red:
            GLenum(GL_RED)
        case .rgb:
            GLenum(GL_RGB)
        case .rgba:
            GLenum(GL_RGBA)
        }
    }
}

/// Uploads image bytes into a reusable OpenGL texture.
@MainActor
struct OpenGLTextureLoader: GLTextureLoader {
    /// Creates and initializes a texture using the image's pixel channel count.
    /// - Parameter image: The bitmap image whose bytes will be uploaded.
    /// - Returns: A texture that owns the allocated OpenGL identifier.
    /// - Throws: `GLTextureError` when the bitmap layout or allocation is invalid.
    func makeTexture(from image: CGImage) throws -> GLTexture {
        guard let data = image.dataProvider?.data else {
            throw GLTextureError.missingPixelData
        }
        guard image.width > 0,
              image.height > 0,
              image.bitsPerComponent == 8,
              image.bitsPerPixel.isMultiple(of: 8) else {
            throw GLTextureError.invalidBitmapLayout
        }

        let channelCount = image.bitsPerPixel / image.bitsPerComponent
        guard (1...4).contains(channelCount) else {
            throw GLTextureError.unsupportedChannelCount(channelCount)
        }

        let outputChannelCount = channelCount == 2 ? 4 : channelCount
        guard let pixelFormat = GLTexturePixelFormat.forChannelCount(channelCount) else {
            throw GLTextureError.unsupportedChannelCount(channelCount)
        }
        let (sourceRowBytes, sourceRowOverflow) = image.width.multipliedReportingOverflow(by: channelCount)
        let (sourceByteCount, sourceSizeOverflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        let (outputRowBytes, outputRowOverflow) = image.width.multipliedReportingOverflow(by: outputChannelCount)
        let (outputByteCount, outputSizeOverflow) = outputRowBytes.multipliedReportingOverflow(by: image.height)
        guard sourceRowOverflow == false,
              sourceSizeOverflow == false,
              outputRowOverflow == false,
              outputSizeOverflow == false,
              image.bytesPerRow >= sourceRowBytes,
              data.count >= sourceByteCount else {
            throw GLTextureError.invalidBitmapLayout
        }

        let uploadData = tightlyPackedData(
            from: data,
            width: image.width,
            height: image.height,
            sourceRowBytes: image.bytesPerRow,
            sourcePixelBytes: channelCount,
            alphaInfo: image.alphaInfo,
            outputByteCount: outputByteCount
        )

        var identifier: GLuint = 0
        glad_glGenTextures(1, &identifier)
        guard identifier != 0 else { throw GLTextureError.allocationFailed }
        glad_glBindTexture(GLenum(GL_TEXTURE_2D), identifier)
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLint(GL_REPEAT))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLint(GL_REPEAT))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLint(GL_LINEAR))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLint(GL_LINEAR))

        var unpackAlignment: GLint = 4
        glad_glGetIntegerv(GLenum(GL_UNPACK_ALIGNMENT), &unpackAlignment)
        glad_glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
        defer { glad_glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), unpackAlignment) }

        uploadData.withUnsafeBytes { bytes in
            glad_glTexImage2D(
                GLenum(GL_TEXTURE_2D),
                0,
                GLint(pixelFormat.openGLValue),
                GLsizei(image.width),
                GLsizei(image.height),
                0,
                pixelFormat.openGLValue,
                GLenum(GL_UNSIGNED_BYTE),
                bytes.baseAddress
            )
        }

        return GLTexture(identifier: identifier)
    }

    /// Removes row padding and expands grayscale-alpha pixels to RGBA.
    private func tightlyPackedData(
        from data: Data,
        width: Int,
        height: Int,
        sourceRowBytes: Int,
        sourcePixelBytes: Int,
        alphaInfo: CGImageAlphaInfo,
        outputByteCount: Int
    ) -> Data {
        var packedData = Data()
        packedData.reserveCapacity(outputByteCount)
        let sourcePixelRowBytes = width * sourcePixelBytes

        for row in 0..<height {
            let rowStart = row * sourceRowBytes
            let rowData = data.subdata(in: rowStart..<(rowStart + sourcePixelRowBytes))
            if sourcePixelBytes == 2 {
                for pixelIndex in stride(from: 0, to: rowData.count, by: 2) {
                    let alphaIndex = alphaInfo == .first || alphaInfo == .premultipliedFirst
                        ? pixelIndex
                        : pixelIndex + 1
                    let grayIndex = alphaIndex == pixelIndex ? pixelIndex + 1 : pixelIndex
                    let gray = rowData[grayIndex]
                    let alpha = rowData[alphaIndex]
                    packedData.append(contentsOf: [gray, gray, gray, alpha])
                }
            } else {
                packedData.append(rowData)
            }
        }

        return packedData
    }
}
