import Foundation

/// A profile that specifies how to interpret a color value for display.
/// 
/// A color space is multi-dimensional, and each dimension represents a specific color component. 
/// For example, the colors in an RGB color space have three dimensions or components—red, green, and blue. 
/// The intensity of each component is represented by floating point values—their range and meaning depends on the color space in question.
/// 
/// Different types of devices (scanners, monitors, printers) operate within different color spaces (RGB, CMYK, grayscale). 
/// Additionally, two devices of the same type (for example, color displays from different manufacturers) may operate within the same kind of color space, yet still produce a different range of colors, or gamut. 
/// Color spaces that are correctly specified ensure that an image has a consistent appearance regardless of the output device.
/// 
/// Core Graphics supports several kinds of color spaces:
///     - Calibrated color spaces ensure that colors appear the same when displayed on different devices. 
///       The visual appearance of the color is preserved, as far as the capabilities of the device allow.
/// 
///     - Device-dependent color spaces are tied to the system of color representation of a particular device. 
///       Device color spaces are not recommended when high-fidelity color preservation is important.
/// 
///     - Special color spaces—indexed and pattern. 
///       An indexed color space contains a color table with up to 256 entries and a base color space to which the color table entries are mapped. 
///       Each entry in the color table specifies one color in the base color space. 
///       A pattern color space is used when stroking or filling with a pattern.
public final class CGColorSpace : Sendable  {

    // MARK: - Creating Color Spaces

    /// Creates a specified type of color space.
    /// - Parameter name: A color space name.
    public init?(name: String) {
        self.name = name
    }

    // MARK: - Examining a Color Space

    /// Returns the name used to create the specified color space.
    public let name: String?

    // MARK: - Accessing System-Defined Color Spaces

    /// The standard Red Green Blue (sRGB) color space.
    public static let sRGB = CGColorSpace(name: "kCGColorSpaceSRGB")!

    /// The generic CMYK color space.
    public static let genericCMYK = CGColorSpace(name: "kCGColorSpaceGenericCMYK")!

    /// The generic RGB color space with a linear transfer function.
    public static let genericRGBLinear = CGColorSpace(name: "kCGColorSpaceGenericRGBLinear")!

    /// The gray color space using a linear transfer function.
    public static let linearGray = CGColorSpace(name: "kCGColorSpaceLinearGray")!

    // MARK: - Instance Methods
    public func isHDR() -> Bool {
        false
    }
}

extension CGColorSpace : CustomStringConvertible {
    public var description: String {
        return "CGColorSpace(name: \(name ?? "nil"))"
    }
}

extension CGColorSpace : Equatable {
    public static func == (lhs: CGColorSpace, rhs: CGColorSpace) -> Bool {
        return lhs.name == rhs.name
    }
}

extension CGColorSpace : Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}