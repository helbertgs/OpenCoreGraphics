import Foundation
@preconcurrency import OpenGLAD
@testable import OpenCoreGraphics

/// A failure to convert framebuffer bytes into the comparison color space.
enum GLComparisonPixelsError: Error, Equatable {
    /// The framebuffer encoding or read attachment was not available.
    case unknownFramebufferEncoding
    /// The comparison requires nonempty opaque RGBA pixels.
    case invalidOpaquePixels
    /// OpenGL reported an error while drawing, reading pixels or querying metadata.
    case graphicsError(UInt32)
    /// The framework could not convert linear RGB to sRGB.
    case colorConversionFailed
}

/// The active read framebuffer and its color encoding.
struct GLComparisonFramebuffer {
    /// Name of the framebuffer bound for reading.
    let readFramebuffer: GLint
    /// The selected color buffer.
    let readBuffer: GLint
    /// The reported framebuffer color encoding.
    let encoding: GLint
    /// Whether framebuffer values are stored with sRGB encoding.
    let storedAsSRGB: Bool

    /// Reads the current framebuffer and verifies its color attachment.
    /// - Throws: `GLComparisonPixelsError` when the read buffer or encoding is invalid.
    @MainActor
    init() throws {
        var framebuffer: GLint = 0
        var readBuffer: GLint = 0
        var encoding: GLint = 0
        glad_glGetIntegerv(GLenum(GL_READ_FRAMEBUFFER_BINDING), &framebuffer)
        glad_glGetIntegerv(GLenum(GL_READ_BUFFER), &readBuffer)
        let attachment: GLenum
        if framebuffer == 0 {
            switch GLenum(readBuffer) {
            case GLenum(GL_BACK), GLenum(GL_BACK_LEFT):
                attachment = GLenum(GL_BACK_LEFT)
            case GLenum(GL_FRONT), GLenum(GL_FRONT_LEFT):
                attachment = GLenum(GL_FRONT_LEFT)
            default:
                throw GLComparisonPixelsError.unknownFramebufferEncoding
            }
        } else {
            guard readBuffer != GLint(GL_NONE) else { throw GLComparisonPixelsError.unknownFramebufferEncoding }
            attachment = GLenum(readBuffer)
        }
        glad_glGetFramebufferAttachmentParameteriv(
            GLenum(GL_READ_FRAMEBUFFER), attachment, GLenum(GL_FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING), &encoding
        )
        let error = glad_glGetError()
        guard error == GLenum(GL_NO_ERROR) else { throw GLComparisonPixelsError.graphicsError(error) }
        guard encoding == GLint(GL_LINEAR) || encoding == GLint(GL_SRGB) else {
            throw GLComparisonPixelsError.unknownFramebufferEncoding
        }
        readFramebuffer = framebuffer
        self.readBuffer = readBuffer
        self.encoding = encoding
        storedAsSRGB = encoding == GLint(GL_SRGB) && glad_glIsEnabled(GLenum(GL_FRAMEBUFFER_SRGB)) == GL_TRUE
    }
}

/// Converts opaque GL framebuffer pixels to sRGB for comparison with the sRGB bitmap target.
struct GLComparisonPixels {
    /// RGBA bytes in the sRGB comparison space, retaining their original row order.
    let data: Data

    /// Reads the active framebuffer encoding and converts its opaque pixels as needed.
    /// - Parameter pixels: Opaque RGBA bytes read from the framebuffer.
    /// - Throws: `GLComparisonPixelsError` when the state or pixels are invalid.
    @MainActor
    init(pixels: Data) throws {
        let framebuffer = try GLComparisonFramebuffer()
        try self.init(pixels: pixels, storedAsSRGB: framebuffer.storedAsSRGB)
    }

    /// Converts known opaque framebuffer bytes to sRGB without querying OpenGL.
    /// - Parameters:
    ///   - pixels: Opaque RGBA bytes in linear RGB or sRGB.
    ///   - storedAsSRGB: Whether RGB components are already sRGB encoded.
    /// - Throws: `GLComparisonPixelsError` for unsupported pixels or conversion.
    init(pixels: Data, storedAsSRGB: Bool) throws {
        guard pixels.isEmpty == false, pixels.count.isMultiple(of: 4) else {
            throw GLComparisonPixelsError.invalidOpaquePixels
        }
        var bytes = [UInt8](pixels)
        guard stride(from: 3, to: bytes.count, by: 4).allSatisfy({ bytes[$0] == 255 }) else {
            throw GLComparisonPixelsError.invalidOpaquePixels
        }
        if storedAsSRGB == false {
            var table: [UInt8] = []
            for value in 0...255 {
                let component = Double(value) / 255
                guard let linear = CGColor(
                    colorSpace: .genericRGBLinear, components: [component, component, component, 1]
                ), let srgb = linear.converted(to: .sRGB) else {
                    throw GLComparisonPixelsError.colorConversionFailed
                }
                table.append(UInt8((srgb.components[0] * 255).rounded()))
            }
            for index in stride(from: 0, to: bytes.count, by: 4) {
                bytes[index] = table[Int(bytes[index])]
                bytes[index + 1] = table[Int(bytes[index + 1])]
                bytes[index + 2] = table[Int(bytes[index + 2])]
            }
        }
        data = Data(bytes)
    }
}
