import Foundation

/// Encodes bitmap surfaces as top-down, 32-bit BMP files with straight alpha.
enum BMPEncoder {
    /// The fixed byte position of the first pixel after the BMP V4 headers.
    private static let pixelDataOffset = 122

    /// Encodes a bitmap surface into a 32-bit BMP V4 data block.
    /// - Parameter surface: The source pixels in the surface's native RGBA or BGRA layout.
    /// - Returns: A complete BMP file with top-down rows and unpremultiplied BGRA pixel bytes.
    /// - Throws: `BMPEncoderError` when the dimensions cannot be represented by the BMP format.
    static func encode(surface: PixelSurface) throws -> Data {
        let (pixelCount, pixelCountOverflow) = surface.width.multipliedReportingOverflow(by: surface.height)
        let (imageByteCount, imageSizeOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        let (fileByteCount, fileSizeOverflow) = imageByteCount.addingReportingOverflow(pixelDataOffset)
        guard pixelCountOverflow == false,
              imageSizeOverflow == false,
              fileSizeOverflow == false,
              surface.width <= Int(Int32.max),
              surface.height <= Int(Int32.max),
              imageByteCount <= Int(UInt32.max),
              fileByteCount <= Int(UInt32.max) else {
            throw BMPEncoderError.dimensionsOutOfRange
        }

        var data = Data()
        data.reserveCapacity(fileByteCount)
        data.append(contentsOf: [0x42, 0x4D])
        append(UInt32(fileByteCount), to: &data)
        append(UInt32(0), to: &data)
        append(UInt32(pixelDataOffset), to: &data)

        append(UInt32(108), to: &data)
        append(UInt32(surface.width), to: &data)
        append(UInt32(bitPattern: -Int32(surface.height)), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(32), to: &data)
        append(UInt32(3), to: &data)
        append(UInt32(imageByteCount), to: &data)
        for _ in 0..<4 {
            append(UInt32(0), to: &data)
        }
        append(UInt32(0x00FF0000), to: &data)
        append(UInt32(0x0000FF00), to: &data)
        append(UInt32(0x000000FF), to: &data)
        append(UInt32(0xFF000000), to: &data)
        append(UInt32(0x73524742), to: &data)
        for _ in 0..<12 {
            append(UInt32(0), to: &data)
        }

        for y in 0..<surface.height {
            for x in 0..<surface.width {
                guard let pixel = surface.pixel(x: x, y: y) else {
                    throw BMPEncoderError.pixelUnavailable
                }
                data.append(unpremultiply(pixel.blue, alpha: pixel.alpha))
                data.append(unpremultiply(pixel.green, alpha: pixel.alpha))
                data.append(unpremultiply(pixel.red, alpha: pixel.alpha))
                data.append(pixel.alpha)
            }
        }
        return data
    }

    /// Encodes pixels supplied by a bitmap context into a 32-bit BMP V4 data block.
    /// - Parameters:
    ///   - bitmapData: The source bytes, including any row padding.
    ///   - width: The bitmap width in pixels.
    ///   - height: The bitmap height in pixels.
    ///   - bytesPerRow: The source row stride in bytes.
    ///   - colorSpace: The color space used to interpret the source pixels.
    ///   - alphaInfo: The source alpha layout.
    ///   - bitmapInfo: The source channel byte order.
    /// - Returns: A complete BMP file with top-down rows and straight alpha.
    /// - Throws: `BMPEncoderError` when the source storage or format is unsupported.
    static func encode(
        bitmapData: Data,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        colorSpace: CGColorSpace,
        alphaInfo: CGImageAlphaInfo,
        bitmapInfo: CGBitmapInfo
    ) throws -> Data {
        let (requiredByteCount, sizeOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard width > 0,
              height > 0,
              bytesPerRow > 0,
              sizeOverflow == false,
              bitmapData.count == requiredByteCount else {
            throw BMPEncoderError.invalidSourceData
        }

        var sourceBytes = [UInt8](bitmapData)
        return try sourceBytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let surface = PixelSurface(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bytesPerRow: bytesPerRow,
                      colorSpace: colorSpace,
                      alphaInfo: alphaInfo,
                      bitmapInfo: bitmapInfo
                  ) else {
                throw BMPEncoderError.unsupportedPixelFormat
            }
            return try encode(surface: surface)
        }
    }

    /// Appends a 16-bit integer in little-endian byte order.
    /// - Parameters:
    ///   - value: The integer to serialize.
    ///   - data: The BMP byte buffer receiving the integer.
    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    /// Appends a 32-bit integer in little-endian byte order.
    /// - Parameters:
    ///   - value: The integer to serialize.
    ///   - data: The BMP byte buffer receiving the integer.
    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    /// Converts one premultiplied color channel to its straight-alpha value.
    /// - Parameters:
    ///   - value: The premultiplied color channel.
    ///   - alpha: The pixel alpha channel.
    /// - Returns: The rounded 8-bit straight-alpha component.
    private static func unpremultiply(_ value: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha > 0 else { return 0 }
        let straightValue = (Int(value) * 255 + Int(alpha) / 2) / Int(alpha)
        return UInt8(min(255, straightValue))
    }
}

/// Failures produced when a surface cannot be represented as a BMP file.
enum BMPEncoderError: Error {
    /// The source bitmap does not contain a valid number of bytes.
    case invalidSourceData

    /// The bitmap dimensions exceed the signed BMP header limits.
    case dimensionsOutOfRange

    /// The source surface uses a pixel format not supported by the encoder.
    case unsupportedPixelFormat

    /// A valid source pixel could not be read from its surface.
    case pixelUnavailable
}
