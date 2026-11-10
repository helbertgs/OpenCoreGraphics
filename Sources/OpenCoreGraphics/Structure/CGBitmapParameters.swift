import Foundation

/// Typed pixel-format settings for creating a bitmap graphics context.
public struct CGBitmapParameters {
    /// The color space used to interpret bitmap color components.
    public var colorSpace: CGColorSpace

    /// The order and presence of color channels in each pixel.
    public var layout: CGBitmapLayout = .rgba

    /// The numeric representation and precision of each component.
    public var component: CGComponent = .integer8Bit

    /// Whether components use integer or floating-point storage.
    public var componentInfo: CGImageComponentInfo = .integer

    /// The location and premultiplication of the alpha component.
    public var alphaInfo: CGImageAlphaInfo = .premultipliedLast

    /// Creates bitmap parameters with a selected color space.
    /// - Parameter colorSpace: The color space to associate with the bitmap.
    init(colorSpace: CGColorSpace = .sRGB) {
        self.colorSpace = colorSpace
    }
}