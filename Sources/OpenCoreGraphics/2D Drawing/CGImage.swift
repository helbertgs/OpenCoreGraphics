import Foundation
import OpenSTB

/// A bitmap image or image mask.
/// 
/// A bitmap (or sampled) image is a rectangular array of pixels, with each pixel representing a single sample or data point in a source image.
public class CGImage : Equatable, Hashable {
    /// Stable token identifying this image instance in renderer caches.
    let textureCacheIdentity = UUID()

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
        self.alphaInfo = .none
    }

    /// Creates an image with an explicit alpha layout for copied bitmap pixels.
    /// - Parameters:
    ///   - width: The width of the image in pixels.
    ///   - height: The height of the image in pixels.
    ///   - bitsPerComponent: The number of bits for each color component.
    ///   - bitsPerPixel: The number of bits used by each pixel.
    ///   - bytesPerRow: The byte distance between row starts.
    ///   - space: The color space of the image.
    ///   - bitmapInfo: The byte-order information for the pixels.
    ///   - provider: The source of pixel data.
    ///   - decode: An optional decode array.
    ///   - shouldInterpolate: Whether image interpolation is enabled.
    ///   - intent: The color rendering intent.
    ///   - alphaInfo: The alpha layout associated with the pixel bytes.
    init(
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
        intent: CGColorRenderingIntent,
        alphaInfo: CGImageAlphaInfo
    ) {
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
        self.alphaInfo = alphaInfo
    }

    /// Loads and decodes an image file into owned RGBA pixel data.
    /// - Parameter url: The path to the image file.
    /// - Returns: A decoded image, or nil if the file is missing, invalid, or too large.
    public init?(url: String) {
        var width: Int32 = 0
        var height: Int32 = 0
        var channels: Int32 = 0
        guard let image = url.withCString({ filename in
            stbi_load(filename, &width, &height, &channels, 4)
        }) else {
            return nil
        }
        defer { stbi_image_free(image) }

        guard width > 0, height > 0, (1...4).contains(channels) else { return nil }
        let (bytesPerRow, rowOverflow) = Int(width).multipliedReportingOverflow(by: 4)
        let (byteCount, dataOverflow) = bytesPerRow.multipliedReportingOverflow(by: Int(height))
        guard rowOverflow == false, dataOverflow == false else { return nil }

        let dataProvider = CGDataProvider(data: Data(bytes: image, count: byteCount))
        self.dataProvider = dataProvider
        self.width = Int(width)
        self.height = Int(height)
        self.bitsPerComponent = 8
        self.bitsPerPixel = 32
        self.bytesPerRow = bytesPerRow
        self.colorSpace = .sRGB
        self.alphaInfo = .last
        self.bitmapInfo = .byteOrder32Big
    }

    // MARK: - Examining an Image

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

    /// Returns whether both image references identify the same image object.
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        lhs === rhs
    }

    /// Hashes this image's object identity by feeding it into the given hasher.
    /// 
    /// Implement this method to conform to the Hashable protocol. 
    /// The components used for hashing must be the same as the components compared in your type’s == operator implementation. 
    /// Call ``hasher.combine(_:)`` with each of these components.
    /// - Parameter hasher: The hasher to use when combining the components of this instance.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

/// An immutable image value that can cross actor boundaries with a draw command.
struct CGImageSnapshot: Equatable, Sendable {
    /// The stable identity of the source image object.
    let identity: UUID

    /// The copied pixel bytes, when the image has a data provider.
    let data: Data?

    /// The image width in pixels.
    let width: Int

    /// The image height in pixels.
    let height: Int

    /// The number of bits in each component.
    let bitsPerComponent: Int

    /// The number of bits in each pixel.
    let bitsPerPixel: Int

    /// The byte stride between the starts of adjacent rows.
    let bytesPerRow: Int

    /// The alpha channel layout of the image.
    let alphaInfo: CGImageAlphaInfo

    /// The color space used to interpret image components.
    let colorSpace: CGColorSpace?

    /// The byte order used to interpret image pixels.
    let bitmapInfo: CGBitmapInfo

    /// Creates an immutable snapshot of an image and its pixel data.
    /// - Parameter image: The image whose state will be captured.
    init(image: CGImage) {
        identity = image.textureCacheIdentity
        data = image.dataProvider?.data
        width = image.width
        height = image.height
        bitsPerComponent = image.bitsPerComponent
        bitsPerPixel = image.bitsPerPixel
        bytesPerRow = image.bytesPerRow
        alphaInfo = image.alphaInfo
        colorSpace = image.colorSpace
        bitmapInfo = image.bitmapInfo
    }
}