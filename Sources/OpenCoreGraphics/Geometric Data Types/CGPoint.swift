import Foundation

/// CGPoint is a structure that represents a point in a two-dimensional coordinate system.
public struct CGPoint : Codable, Equatable, Hashable, Sendable {

    /// X coordinate of the point.
    public var x: Double

    /// Y coordinate of the point.
    public var y: Double

    // MARK: - Initializers

    /// Creates a new point with the specified x and y coordinates.
    /// - Parameters:
    ///   - x: X coordinate of the point.
    ///   - y: Y coordinate of the point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Creates a new point with the specified x and y coordinates.
    /// - Parameters:
    ///   - x: X coordinate of the point.
    ///   - y: Y coordinate of the point.
    /// - Note: This initializer converts the integer values to Double.
    public init(x: Int, y: Int) {
        self.x = Double(x)
        self.y = Double(y)
    }

    /// Creates a new point with the specified x and y coordinates.
    /// - Parameters:
    ///   - x: X coordinate of the point.
    ///   - y: Y coordinate of the point.
    /// - Note: This initializer converts the integer values to Double.
    public init(x: Int32, y: Int32) {
        self.x = Double(x)
        self.y = Double(y)
    }

    // MARK: - Type Properties

    /// A point with coordinates (0, 0).
    public static var zero: CGPoint {
        .init(x: 0, y: 0)
    }

    // MARK: - Transforming Points

    /// Returns the point resulting from an affine transformation of an existing point.
    /// - Parameter t: The affine transform to apply.
    /// - Returns: A new point resulting from applying the specified affine transform to the existing point.
    public func applying(_ t: CGAffineTransform) -> CGPoint {
        let x = self.x * t.m11 + self.y * t.m21 + t.m41
        let y = self.x * t.m12 + self.y * t.m22 + t.m42
        return CGPoint(x: x, y: y)
    }
}

extension CGPoint {
    /// Adds two points together.
    /// - Parameters:
    ///   - lhs: The left-hand side point. 
    ///   - rhs: The right-hand side point.
    /// - Returns: A new point that is the sum of the two points.
    /// Complexity: O(1)
    public static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    /// Subtracts one point from another.
    /// - Parameters:
    ///   - lhs: The left-hand side point.
    ///   - rhs: The right-hand side point.
    /// - Returns: A new point that is the difference of the two points.
    /// Complexity: O(1)
    public static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    /// Multiplies a point by a scalar value.
    /// - Parameters:
    ///   - lhs: The left-hand side point. 
    ///   - rhs: The right-hand side scalar value.
    /// - Returns: A new point that is the product of the point and the scalar.
    /// Complexity: O(1)
    public static func * (lhs: CGPoint, rhs: Double) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    /// Multiplies a scalar value by a point.
    /// - Parameters:
    ///   - lhs: The left-hand side scalar value.
    ///   - rhs: The right-hand side point.
    /// - Returns: A new point that is the product of the scalar and the point.
    /// Complexity: O(1)
    public static func * (lhs: Double, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs * rhs.x, y: lhs * rhs.y)
    }

    /// Divides a point by a scalar value.
    /// - Parameters:
    ///   - lhs: The left-hand side point.
    ///   - rhs: The right-hand side scalar value.
    /// - Returns: A new point that is the quotient of the point and the scalar.
    /// - Note: This operation will throw an exception if the scalar is zero.
    /// Complexity: O(1)
    public static func / (lhs: CGPoint, rhs: Double) -> CGPoint {
        guard rhs != 0 else { fatalError("Division by zero") }
        return CGPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    /// Divides a scalar value by a point.
    /// - Parameters:
    ///   - lhs: The left-hand side scalar value.
    ///   - rhs: The right-hand side point.
    /// - Returns: A new point that is the quotient of the scalar and the point.
    /// - Note: This operation will throw an exception if either coordinate of the point is zero.
    /// Complexity: O(1)
    public static func / (lhs: Double, rhs: CGPoint) -> CGPoint {
        guard rhs.x != 0 && rhs.y != 0 else { fatalError("Division by zero") }
        return CGPoint(x: lhs / rhs.x, y: lhs / rhs.y)
    }
}