import Foundation

/// A color ramp made from ordered color stops.
public struct CGGradient: Equatable, Sendable {
    /// The maximum number of stops supported by the software and OpenGL renderers.
    public static let maximumColorCount = 128

    /// The colors in this gradient, in the same order as their locations.
    public let colors: [CGColor]

    /// The normalized positions of the corresponding colors.
    public let locations: [Double]

    /// Creates a gradient from at least two colors and their normalized positions.
    /// - Parameters:
    ///   - colors: The colors that define the gradient ramp.
    ///   - locations: The positions of each color in the inclusive range `0...1`.
    /// - Returns: A gradient, or `nil` when the stops are invalid or exceed the renderer limit.
    public init?(colors: [CGColor], locations: [Double]) {
        guard colors.count >= 2,
              colors.count <= Self.maximumColorCount,
              colors.count == locations.count,
              locations.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              zip(locations, locations.dropFirst()).allSatisfy({ $0.0 <= $0.1 }) else {
            return nil
        }

        self.colors = colors
        self.locations = locations
    }
}

/// Controls whether a gradient extends beyond its first or last color stop.
public struct CGGradientDrawingOptions: OptionSet, Sendable {
    /// The integer representation of the selected gradient options.
    public let rawValue: UInt

    /// Creates options from their raw bit representation.
    /// - Parameter rawValue: The option bits to store.
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Fills points before the first stop with the first stop's color.
    public static let drawsBeforeStartLocation = Self(rawValue: 1 << 0)

    /// Fills points after the last stop with the last stop's color.
    public static let drawsAfterEndLocation = Self(rawValue: 1 << 1)
}
