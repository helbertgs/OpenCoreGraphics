import Foundation
import OpenSTB
@preconcurrency import OpenGLAD 

/// A bitmap image or image mask.
/// 
/// A bitmap (or sampled) image is a rectangular array of pixels, with each pixel representing a single sample or data point in a source image.
public class CGImage : Equatable, Hashable, Identifiable {

    // MARK: - Creating Images
    
    /// Creates a bitmap image from data supplied by a data provider.
    /// 
    /// The data provider should provide raw data that matches the format specified by the other input parameters. 
    /// To use encoded data (for example, from a file specified by a URL-based data provider), see ``init(jpegDataProviderSource:decode:shouldInterpolate:intent:)`` and ``init(pngDataProviderSource:decode:shouldInterpolate:intent:)``.
    /// - Parameters:
    ///   - width: The width, in pixels, of the required image.
    ///   - height: The height, in pixels, of the required image
    ///   - bitsPerComponent: The number of bits for each component in a source pixel. For example, if the source image uses the RGBA-32 format, you would specify 8 bits per component.
    ///   - bitsPerPixel: The total number of bits in a source pixel. This value must be at least bitsPerComponent times the number of components per pixel.
    ///   - bytesPerRow: The number of bytes of memory for each horizontal row of the bitmap.
    ///   - space: The color space for the image.
    ///   - bitmapInfo: A constant that specifies whether the bitmap should contain an alpha channel and its relative location in a pixel, along with whether the components are floating-point or integer values.
    ///   - provider: The source of data for the bitmap.
    ///   - decode: The decode array for the image. If you do not want to allow remapping of the image’s color values, pass nil for the decode array. For each color component in the image’s color space (including the alpha component), a decode array provides a pair of values denoting the upper and lower limits of a range. For example, the decode array for a source image in the RGB color space would contain six entries total, consisting of one pair each for red, green, and blue. When the image is rendered, Core Graphics uses a linear transform to map the original component value into a relative number within your designated range that is appropriate for the destination color space.
    ///   - shouldInterpolate: A Boolean value that specifies whether interpolation should occur. The interpolation setting specifies whether Core Graphics should apply a pixel-smoothing algorithm to the image. Without interpolation, the image may appear jagged or pixelated when drawn on an output device with higher resolution than the image data.
    ///   - intent: A rendering intent constant that specifies how Core Graphics should handle colors that are not located within the gamut of the destination color space of a graphics context. The rendering intent determines the exact method used to map colors from one color space to another.
    public init(
        width: Int,
        height: Int,
        bitsPerComponent: Int,
        bitsPerPixel: Int,
        bytesPerRow: Int,
        space: CGColorSpace,
        bitmapInfo: CGBitmapInfo,
        provider: CGDataProvider,
        decode: UnsafePointer<CGFloat>?,
        shouldInterpolate: Bool,
        intent: CGColorRenderingIntent
    ) {
        self.id = 0
        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        self.bitsPerPixel = bitsPerPixel
        self.bytesPerRow = bytesPerRow
        self.colorSpace = space
        self.bitmapInfo = bitmapInfo
        self.dataProvider = provider
        self.decode = decode
        self.shouldInterpolate = shouldInterpolate
        self.renderingIntent = intent
    }

    public init(url: String) {
        var width: Int32 = 0
        var height: Int32 = 0
        var channels: Int32 = 0
        var format: Int32 = GL_RGBA

        stbi_set_flip_vertically_on_load(1)
        
        guard let image: UnsafeMutablePointer<UInt8> = stbi_load(url, &width, &height, &channels, 0) else {
            fatalError("failed to load image: \(url)")
        }

        let data  = Data(bytes: image, count: Int(width * height * channels))
        let dataProvider = CGDataProvider(data: data)
        dataProvider.info = image
        
        self.dataProvider = dataProvider
        self.width = Int(width)
        self.height = Int(height)
        self.colorSpace = channels == 4 ? CGColorSpace.sRGB : CGColorSpace.genericRGBLinear
        format = channels == 4 ? GL_RGBA : GL_RGB

        stbi_image_free(image)

        var id = UInt32(0)
        glad_glGenTextures(1, &id)
        defer { glad_glDeleteTextures(1, &id) }
        glad_glBindTexture(GLenum(GL_TEXTURE_2D), id)
        
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLint(GL_REPEAT))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLint(GL_REPEAT))
        
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLint(GL_LINEAR))
        glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLint(GL_LINEAR))

        dataProvider.data?.withUnsafeMutableBytes {
            glad_glTexImage2D(GLenum(GL_TEXTURE_2D), 0,  format,  GLsizei(width),  GLsizei(height),  0,  GLenum(format),  GLenum(GL_UNSIGNED_BYTE),  $0.baseAddress)
        }

        glad_glGenerateMipmap(GLenum(GL_TEXTURE_2D))
    }

    // MARK: - Examining an Image

    public private(set) var id: UInt32 = 0

    /// Returns whether a bitmap image is an image mask.
    public private(set) var isMask: Bool = false

    /// Returns the width of a bitmap image, in pixels.
    public private(set) var width: Int = 0

    /// Returns the height of a bitmap image.
    public private(set) var height: Int = 0

    /// Returns the number of bits allocated for a single color component of a bitmap image.
    public private(set) var bitsPerComponent: Int = 0

    /// Returns the number of bits allocated for a single pixel in a bitmap image.
    public private(set) var bitsPerPixel: Int = 0

    /// Returns the number of bytes allocated for a single row of a bitmap image.
    public private(set) var bytesPerRow: Int = 0

    /// Return the color space for a bitmap image.
    public private(set) var colorSpace: CGColorSpace? = nil

    /// Returns the alpha channel information for a bitmap image.
    public private(set) var alphaInfo: CGImageAlphaInfo = .none

    /// Returns the data provider for a bitmap image or image mask.
    public private(set) var dataProvider: CGDataProvider? = nil

    /// Returns the decode array for a bitmap image.
    public private(set) var decode: UnsafePointer<CGFloat>? = nil

    /// Returns the interpolation setting for a bitmap image.
    public private(set) var shouldInterpolate: Bool = false

    /// Returns the rendering intent setting for a bitmap image.
    public private(set) var renderingIntent: CGColorRenderingIntent = .defaultIntent

    /// Returns the bitmap information for a bitmap image.
    public private(set) var bitmapInfo: CGBitmapInfo = .floatComponents

    // MARK: - Equatable and Hashable

    /// Returns a Boolean value indicating whether two values are equal.
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        lhs.id == rhs.id && 
        lhs.isMask == rhs.isMask &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.bitsPerComponent == rhs.bitsPerComponent &&
        lhs.bitsPerPixel == rhs.bitsPerPixel &&
        lhs.bytesPerRow == rhs.bytesPerRow &&
        lhs.colorSpace == rhs.colorSpace
    }

    /// Hashes the essential components of this value by feeding them into the given hasher.
    /// 
    /// Implement this method to conform to the Hashable protocol. 
    /// The components used for hashing must be the same as the components compared in your type’s == operator implementation. 
    /// Call ``hasher.combine(_:)`` with each of these components.
    /// - Parameter hasher: The hasher to use when combining the components of this instance.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isMask)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(bitsPerComponent)
        hasher.combine(bitsPerPixel)
        hasher.combine(bytesPerRow)
        hasher.combine(colorSpace)
    }
}