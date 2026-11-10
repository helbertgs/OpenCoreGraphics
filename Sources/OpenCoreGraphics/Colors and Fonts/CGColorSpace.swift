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
public enum CGColorSpace : String, CaseIterable, Codable, Equatable, Hashable, Sendable  {

    // MARK: - Accessing System-Defined Color Spaces

    /// The standard Red Green Blue (sRGB) color space.
    case sRGB

    /// The generic CMYK color space.
    case genericCMYK

    /// The generic RGB color space with a linear transfer function.
    case genericRGBLinear

    /// The gray color space using a linear transfer function.
    case linearGray

    // MARK: - Inspecting a Color Space

    /// The enum name used to identify this color space.
    public var name: String {
        rawValue
    }

    /// The color model used by this color space.
    public var model: CGColorModel {
        switch self {
        case .sRGB, .genericRGBLinear:
            .rgb
        case .genericCMYK:
            .cmyk
        case .linearGray:
            .gray
        }
    }

    /// The number of color components, excluding alpha, in this color space.
    public var numberOfComponents: Int {
        switch self {
        case .sRGB, .genericRGBLinear:
            3
        case .genericCMYK:
            4
        case .linearGray:
            1
        }
    }

    // MARK: - Instance Methods

    /// Indicates whether the color space supports high-dynamic-range colors.
    public func isHDR() -> Bool {
        false
    }
}

extension CGColorSpace : CustomStringConvertible {
    public var description: String {
        return "CGColorSpace.\(rawValue)"
    }
}