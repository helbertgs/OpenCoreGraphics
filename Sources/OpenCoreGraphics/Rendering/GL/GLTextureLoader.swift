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
    func makeTexture(from image: CGImageSnapshot) throws -> GLTexture {
        let prepared = try uploadData(for: image)

        var identifier: GLuint = 0
        glad_glGenTextures(1, &identifier)
        guard identifier != 0 else { throw GLTextureError.allocationFailed }
        glad_glBindTexture(GLenum(GL_TEXTURE_2D), identifier)
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLint(GL_REPEAT))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLint(GL_REPEAT))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLint(GL_LINEAR))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLint(GL_LINEAR))

        upload(prepared.data, width: image.width, height: image.height, pixelFormat: prepared.pixelFormat)

        return GLTexture(identifier: identifier, width: image.width, height: image.height)
    }

    /// Replaces the pixels in an existing texture, reallocating storage only when dimensions change.
    /// - Parameters:
    ///   - texture: The texture whose contents should be replaced.
    ///   - image: The latest image snapshot.
    /// - Throws: `GLTextureError` when the bitmap layout or pixel data is invalid.
    func updateTexture(_ texture: GLTexture, from image: CGImageSnapshot) throws {
        let prepared = try uploadData(for: image)
        glad_glBindTexture(GLenum(GL_TEXTURE_2D), texture.identifier)

        if texture.width == image.width, texture.height == image.height {
            var unpackAlignment: GLint = 4
            glad_glGetIntegerv(GLenum(GL_UNPACK_ALIGNMENT), &unpackAlignment)
            glad_glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
            defer { glad_glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), unpackAlignment) }

            prepared.data.withUnsafeBytes { bytes in
                glad_glTexSubImage2D(
                    GLenum(GL_TEXTURE_2D),
                    0,
                    0,
                    0,
                    GLsizei(image.width),
                    GLsizei(image.height),
                    prepared.pixelFormat.openGLValue,
                    GLenum(GL_UNSIGNED_BYTE),
                    bytes.baseAddress
                )
            }
        } else {
            upload(prepared.data, width: image.width, height: image.height, pixelFormat: prepared.pixelFormat)
            texture.updateDimensions(width: image.width, height: image.height)
        }
    }

    /// Packs supported source pixels into tightly packed premultiplied upload bytes.
    /// - Parameter image: The immutable bitmap snapshot to prepare.
    /// - Returns: Packed bytes and their matching OpenGL format.
    /// - Throws: `GLTextureError` when the bitmap layout or pixel data is invalid.
    func uploadData(for image: CGImageSnapshot) throws -> (data: Data, pixelFormat: GLTexturePixelFormat) {
        guard let data = image.data else {
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

        return (
            try tightlyPackedData(
                from: data,
                width: image.width,
                height: image.height,
                sourceRowBytes: image.bytesPerRow,
                sourcePixelBytes: channelCount,
                alphaInfo: image.alphaInfo,
                bitmapInfo: image.bitmapInfo,
                colorSpace: image.colorSpace,
                outputByteCount: outputByteCount
            ),
            pixelFormat
        )
    }

    /// Uploads bytes and initializes the texture's storage.
    /// - Parameters:
    ///   - data: Tightly packed pixels.
    ///   - width: The texture width in pixels.
    ///   - height: The texture height in pixels.
    ///   - pixelFormat: The OpenGL format matching the packed pixels.
    private func upload(
        _ data: Data,
        width: Int,
        height: Int,
        pixelFormat: GLTexturePixelFormat
    ) {
        var unpackAlignment: GLint = 4
        glad_glGetIntegerv(GLenum(GL_UNPACK_ALIGNMENT), &unpackAlignment)
        glad_glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
        defer { glad_glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), unpackAlignment) }

        data.withUnsafeBytes { bytes in
            glad_glTexImage2D(
                GLenum(GL_TEXTURE_2D),
                0,
                GLint(pixelFormat.openGLValue),
                GLsizei(width),
                GLsizei(height),
                0,
                pixelFormat.openGLValue,
                GLenum(GL_UNSIGNED_BYTE),
                bytes.baseAddress
            )
        }
    }

    /// Removes row padding, normalizes alpha layouts, and prepares linear premultiplied channels.
    /// - Parameters:
    ///   - data: The validated source pixel bytes.
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    ///   - sourceRowBytes: The byte distance between source row starts.
    ///   - sourcePixelBytes: The number of bytes occupied by each source pixel.
    ///   - alphaInfo: The alpha layout used by each pixel.
    ///   - bitmapInfo: The byte order used by each pixel.
    ///   - colorSpace: The color space used to interpret the source RGB channels.
    ///   - outputByteCount: The number of packed bytes to reserve.
    /// - Throws: `GLTextureError.invalidBitmapLayout` for unsupported alpha-only pixels.
    private func tightlyPackedData(
        from data: Data,
        width: Int,
        height: Int,
        sourceRowBytes: Int,
        sourcePixelBytes: Int,
        alphaInfo: CGImageAlphaInfo,
        bitmapInfo: CGBitmapInfo,
        colorSpace: CGColorSpace?,
        outputByteCount: Int
    ) throws -> Data {
        var packedData = Data()
        packedData.reserveCapacity(outputByteCount)
        let sourcePixelRowBytes = width * sourcePixelBytes

        for row in 0..<height {
            let rowStart = row * sourceRowBytes
            let rowData = data.subdata(in: rowStart..<(rowStart + sourcePixelRowBytes))
            if sourcePixelBytes == 3, colorSpace == .sRGB {
                for pixelIndex in stride(from: 0, to: rowData.count, by: 3) {
                    let color = CGColor(
                        sred: Double(rowData[pixelIndex]) / 255,
                        green: Double(rowData[pixelIndex + 1]) / 255,
                        blue: Double(rowData[pixelIndex + 2]) / 255,
                        alpha: 1
                    )
                    guard let linearColor = color.converted(to: .genericRGBLinear) else {
                        throw GLTextureError.invalidBitmapLayout
                    }
                    packedData.append(contentsOf: linearColor.components.prefix(3).map(byte))
                }
            } else if sourcePixelBytes == 2 {
                for pixelIndex in stride(from: 0, to: rowData.count, by: 2) {
                    let grayIndex: Int
                    let alphaIndex: Int?
                    switch alphaInfo {
                    case .first, .premultipliedFirst:
                        grayIndex = pixelIndex + 1
                        alphaIndex = pixelIndex
                    case .last, .premultipliedLast:
                        grayIndex = pixelIndex
                        alphaIndex = pixelIndex + 1
                    case .noneSkipFirst:
                        grayIndex = pixelIndex + 1
                        alphaIndex = nil
                    case .none, .noneSkipLast:
                        grayIndex = pixelIndex
                        alphaIndex = nil
                    case .alphaOnly:
                        throw GLTextureError.invalidBitmapLayout
                    }
                    let gray = rowData[grayIndex]
                    let alpha = alphaIndex.map { rowData[$0] } ?? 255
                    let premultipliedGray = isPremultiplied(alphaInfo)
                        ? gray
                        : premultiply(gray, alpha: alpha)
                    packedData.append(contentsOf: [
                        premultipliedGray,
                        premultipliedGray,
                        premultipliedGray,
                        alpha
                    ])
                }
            } else if sourcePixelBytes == 4 {
                guard let indices = rgbaComponentIndices(alphaInfo: alphaInfo, bitmapInfo: bitmapInfo) else {
                    throw GLTextureError.invalidBitmapLayout
                }
                for pixelIndex in stride(from: 0, to: rowData.count, by: 4) {
                    let alpha = indices.alpha.map { rowData[pixelIndex + $0] } ?? 255
                    let red = rowData[pixelIndex + indices.red]
                    let green = rowData[pixelIndex + indices.green]
                    let blue = rowData[pixelIndex + indices.blue]
                    if colorSpace == .sRGB {
                        let alphaComponent = Double(alpha) / 255
                        let sourceRGB: [Double]
                        if isPremultiplied(alphaInfo) {
                            sourceRGB = alpha == 0
                                ? [0, 0, 0]
                                : [
                                    min(1, Double(red) / Double(alpha)),
                                    min(1, Double(green) / Double(alpha)),
                                    min(1, Double(blue) / Double(alpha))
                                ]
                        } else {
                            sourceRGB = [red, green, blue].map { Double($0) / 255 }
                        }
                        let color = CGColor(
                            sred: sourceRGB[0],
                            green: sourceRGB[1],
                            blue: sourceRGB[2],
                            alpha: 1
                        )
                        guard let linearColor = color.converted(to: .genericRGBLinear) else {
                            throw GLTextureError.invalidBitmapLayout
                        }
                        packedData.append(contentsOf: linearColor.components.prefix(3).map {
                            byte($0 * alphaComponent)
                        })
                        packedData.append(alpha)
                    } else if isPremultiplied(alphaInfo) || indices.alpha == nil {
                        packedData.append(contentsOf: [red, green, blue, alpha])
                    } else {
                        packedData.append(contentsOf: [
                            premultiply(red, alpha: alpha),
                            premultiply(green, alpha: alpha),
                            premultiply(blue, alpha: alpha),
                            alpha
                        ])
                    }
                }
            } else {
                packedData.append(rowData)
            }
        }

        return packedData
    }

    /// Converts a normalized linear component into its nearest 8-bit channel value.
    /// - Parameter component: A color or alpha value in the unit range.
    /// - Returns: The rounded channel byte.
    private func byte(_ component: Double) -> UInt8 {
        UInt8((min(1, max(0, component)) * 255).rounded())
    }

    /// Resolves the red, green, blue, and optional alpha byte positions for a 32-bit pixel.
    /// - Parameters:
    ///   - alphaInfo: The source alpha placement and premultiplication state.
    ///   - bitmapInfo: The source pixel byte order.
    /// - Returns: The channel positions, or nil for alpha-only data.
    private func rgbaComponentIndices(
        alphaInfo: CGImageAlphaInfo,
        bitmapInfo: CGBitmapInfo
    ) -> (red: Int, green: Int, blue: Int, alpha: Int?)? {
        let isLittleEndian = bitmapInfo == .byteOrder32Little
        return switch alphaInfo {
        case .first, .premultipliedFirst:
            isLittleEndian ? (2, 1, 0, 3) : (1, 2, 3, 0)
        case .last, .premultipliedLast:
            isLittleEndian ? (3, 2, 1, 0) : (0, 1, 2, 3)
        case .noneSkipFirst:
            isLittleEndian ? (2, 1, 0, nil) : (1, 2, 3, nil)
        case .noneSkipLast:
            isLittleEndian ? (3, 2, 1, nil) : (0, 1, 2, nil)
        case .none:
            isLittleEndian ? (2, 1, 0, nil) : (0, 1, 2, nil)
        case .alphaOnly:
            nil
        }
    }

    /// Returns whether the source alpha layout already stores premultiplied color channels.
    /// - Parameter alphaInfo: The source alpha placement and premultiplication state.
    /// - Returns: True when RGB values already include alpha.
    private func isPremultiplied(_ alphaInfo: CGImageAlphaInfo) -> Bool {
        alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
    }

    /// Multiplies an 8-bit straight-alpha color channel by its alpha.
    /// - Parameters:
    ///   - component: The unpremultiplied channel value.
    ///   - alpha: The alpha channel value.
    /// - Returns: The rounded premultiplied channel.
    private func premultiply(_ component: UInt8, alpha: UInt8) -> UInt8 {
        UInt8((UInt16(component) * UInt16(alpha) + 127) / 255)
    }
}
