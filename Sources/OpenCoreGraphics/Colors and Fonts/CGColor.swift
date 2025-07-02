import Foundation

/// A set of components that define a color, with a color space specifying how to interpret them.
/// 
/// CGColor is the fundamental data type used internally by Core Graphics to represent colors. 
/// CGColor objects, and the functions that operate on them, provide a fast and convenient way of managing and setting colors directly, especially colors that are reused (such as black for text).
/// 
/// A color object contains a set of components (such as red, green, and blue) that uniquely define a color, and a color space that specifies how those components should be interpreted.
/// 
/// Color objects provide a fast and convenient way to manage and set colors, especially colors that are used repeatedly. 
/// Drawing operations use color objects for setting fill and stroke colors, managing alpha, and setting color with a pattern.
public final class CGColor : Sendable {

    // MARK: - Creating Colors

    /// Creates a copy of an existing color.
    /// - Returns: A copy of the specified color.
    public func copy() -> CGColor? {
        guard let colorSpace = self.colorSpace else { 
            return nil 
        }

        return CGColor(colorSpace: colorSpace, components: components)
    }

    /// Creates a copy of an existing color, substituting a new alpha value.
    /// - Parameter alpha: A value that specifies the desired opacity of the copy. Values outside the range [0,1] are clamped to 0 or 1.
    /// - Returns: A copy of the specified color, using the specified alpha value. 
    public func copy(alpha: Float) -> CGColor? {
        guard let colorSpace = self.colorSpace else { 
            return nil 
        }

        var components = self.components
        components[components.count - 1] = alpha

        return CGColor(colorSpace: colorSpace, components: components)
    }

    /// Creates a color in the Generic CMYK color space.
    /// - Parameters:
    ///   - cyan: A cyan value (0.0 - 1.0).
    ///   - magenta: A magenta value (0.0 - 1.0).
    ///   - yellow: A yellow value (0.0 - 1.0).
    ///   - black: A black value (0.0 - 1.0).
    ///   - alpha: An alpha value (0.0 - 1.0).
    public init(cyan: Float, magenta: Float, yellow: Float, black: Float, alpha: Float) {
        self.alpha = alpha
        self.components = [cyan, magenta, yellow, black, alpha]
        self.colorSpace = .genericCMYK
    }

    /// Creates a color in the Generic gray color space.
    /// - Parameters:
    ///   - gray: A grayscale value (0.0 - 1.0).
    ///   - alpha: An alpha value (0.0 - 1.0).
    public init(gray: Float, alpha: Float) {
        self.alpha = alpha
        self.components = [gray, alpha]
        self.colorSpace = .linearGray
    }

    /// Creates a color in the Generic RGB color space.
    /// - Parameters:
    ///   - red: A red component value (0.0 - 1.0).
    ///   - green: A green component value (0.0 - 1.0).
    ///   - blue: A blue component value (0.0 - 1.0).
    ///   - alpha: An alpha value (0.0 - 1.0).
    public init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.alpha = alpha
        self.components = [red, green, blue, alpha]
        self.colorSpace = .genericRGBLinear
    }

    /// Creates a color in the sRGB color space.
    /// - Parameters:
    ///   - red: A red component value (0.0 - 1.0).
    ///   - green: A green component value (0.0 - 1.0).
    ///   - blue: A blue component value (0.0 - 1.0).
    ///   - alpha: An alpha value (0.0 - 1.0).
    public init(sred: Float, green: Float, blue: Float, alpha: Float) {
        self.alpha = alpha
        self.components = [sred, green, blue, alpha]
        self.colorSpace = .sRGB
    }

    // MARK: - Getting System Colors

    /// The black color in the Generic gray color space.
    public static let black =  CGColor(red: 0, green: 0, blue: 0, alpha: 1)

    /// The white color in the Generic gray color space.
    public static let white =  CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    /// The clear color in the Generic gray color space.
    public static let clear =  CGColor(red: 0, green: 0, blue: 0, alpha: 0)

    /// Creates a color using a list of intensity values (including alpha) and an associated color space.
    /// - Parameters:
    ///   - space: A color space for the new color.
    ///   - components: An array of intensity values describing the color. 
    ///                 The array should contain n+1 values that correspond to the n color components in the specified color space, followed by the alpha component. 
    ///                 Each component value should be in the range appropriate for the color space. 
    ///                 Values outside this range will be clamped to the nearest correct value.
    public init?(colorSpace space: CGColorSpace, components: [Float]) {
        self.colorSpace = space
        self.components = components
        self.alpha = components.last ?? 1.0
    }

    // MARK: - Examining a Color

    /// Returns the value of the alpha component associated with a color.
    public let alpha: Float

    /// Returns the color space associated with a color.
    public let colorSpace: CGColorSpace?

    /// Returns the values of the color components (including alpha) associated with a color.
    /// 
    /// An array of intensity values for the color components (including alpha) associated with the specified color. 
    /// The size of the array is equal to the color’s numberOfComponents value.
    public let components: [Float]

    /// Returns the number of color components (including alpha) associated with a color.
    public var numberOfComponents: Int {
        components.count
    }
}

extension CGColor : CustomStringConvertible {
    public var description: String {
        return "CGColor(colorSpace: \(colorSpace?.description ?? "nil"), components: \(components), alpha: \(alpha))"
    }
}
extension CGColor : Equatable {
    public static func == (lhs: CGColor, rhs: CGColor) -> Bool {
        return lhs.colorSpace == rhs.colorSpace && lhs.components == rhs.components && lhs.alpha == rhs.alpha
    }
}

extension CGColor : Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(colorSpace)
        hasher.combine(components)
        hasher.combine(alpha)
    }
}