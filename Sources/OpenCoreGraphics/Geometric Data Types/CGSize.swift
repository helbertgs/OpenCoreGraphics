import Foundation

/// A structure that contains width and height values.
public struct CGSize : Codable, Equatable, Hashable, Sendable {

    // MARK: -  Geometric Properties

    /// A width value.
    public var width: Double

    /// A height value.
    public var height: Double

    // MARK: -  Initializers

    /// Creates a new size structure with the specified width and height.
    /// - Parameters:
    ///   - width: A width value.
    ///   - height: A height value.
    /// - Returns: A new size structure with the specified width and height.
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// Creates a new size structure with the specified width and height.
    /// - Parameters:
    ///   - width: A width value.
    ///   - height: A height value.
    /// - Returns: A new size structure with the specified width and height.
    /// - Note: The width and height values are converted to `Double`.
    public init(width: Int, height: Int) {
        self.width = Double(width)
        self.height = Double(height)
    }

     /// Creates a new size structure with the specified width and height.
    /// - Parameters:
    ///   - width: A width value.
    ///   - height: A height value.
    /// - Returns: A new size structure with the specified width and height.
    /// - Note: The width and height values are converted to `Double`.
    public init(width: Int32, height: Int32) {
        self.width = Double(width)
        self.height = Double(height)
    }

    // MARK: - Special Values
    
    /// A size structure with zero width and height.
    public static var zero: CGSize { 
        CGSize(width: 0, height: 0)
    }

    // MARK: - Transforming Sizes

    /// Applies a transformation to the size.
    /// - Parameter t: The transformation to apply.
    /// - Returns: Results in a new size structure with the transformed width and height.
    public func applying(_ t: CGAffineTransform) -> CGSize {
        let x = self.width * t.m11 + self.height * t.m21
        let y = self.width * t.m12 + self.height * t.m22
        return CGSize(width: x, height: y)
    }
} 