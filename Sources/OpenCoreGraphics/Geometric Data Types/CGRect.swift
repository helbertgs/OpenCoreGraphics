import Foundation

/// A structure that represents a rectangle in a two-dimensional coordinate system.
public struct CGRect : Codable, Equatable, Hashable, Sendable {

    /// Creates a rectangle with the specified origin and size.
    /// - Parameters:
    ///   - origin: The origin of the rectangle.
    ///   - size: The size of the rectangle.
    public init(origin: CGPoint, size: CGSize) {
        self.origin = origin
        self.size = size
    }

    /// Creates a rectangle with the specified origin and size.
    /// - Parameters:
    ///   - x: X-coordinate of the rectangle's origin.
    ///   - y: Y-coordinate of the rectangle's origin.
    ///   - width: A value that represents the width of the rectangle.
    ///   - height: A value that represents the height of the rectangle.
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = CGPoint(x: x, y: y)
        self.size = CGSize(width: width, height: height)
    }

    /// Creates a rectangle with the specified origin and size.
    /// - Parameters:
    ///   - x: X-coordinate of the rectangle's origin.
    ///   - y: Y-coordinate of the rectangle's origin.
    ///   - width: A value that represents the width of the rectangle.
    ///   - height: A value that represents the height of the rectangle.
    /// - Note: This initializer converts the integer values to Double.
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.origin = CGPoint(x: x, y: y)
        self.size = CGSize(width: width, height: height)
    }

    // MARK: - Instance Properties

    /// The origin of the rectangle.
    public var origin: CGPoint

    /// The size of the rectangle.
    public var size: CGSize

    /// The height of the rectangle.
    public var height: Double {
        size.height
    }

    /// The width of the rectangle.
    public var width: Double {
        size.width
    }

    /// A Boolean value indicating whether the rectangle is infinite.
    /// 
    /// - Note: A rectangle is considered infinite if its width or height is infinite.
    public var isInfinite: Bool {
        self == .infinite
    }

    /// A Boolean value indicating whether the rectangle is empty.
    /// 
    /// - Note: A rectangle is considered null if its width or height is equal to .nan.
    public var isNull: Bool {
        self == .null
    }

    /// A Boolean value indicating whether the rectangle is empty.
    /// 
    /// - Note: A rectangle is considered empty if its width or height is equal to 0.
    public var isEmpty: Bool {
        self == .zero
    }

    /// The maximum x-coordinate of the rectangle.
    public var maxX: Double {
        origin.x + size.width
    }

    /// The maximum y-coordinate of the rectangle.
    public var maxY: Double {
        origin.y + size.height
    }

    /// The midpoint x-coordinate of the rectangle.
    public var midX: Double {
        origin.x + size.width / 2
    }

    /// The midpoint y-coordinate of the rectangle.
    public var midY: Double {
        origin.y + size.height / 2
    }

    /// The minimum x-coordinate of the rectangle.
    public var minX: Double {
        origin.x
    }

    /// The minimum y-coordinate of the rectangle.
    public var minY: Double {
        origin.y
    }

    // MARK: - Type Properties

    // Return a rectangle that represents infinity.
    public static var infinite: CGRect {
        .init(x: .infinity, y: .infinity, width: .infinity, height: .infinity)
    }

    /// A rectangle that represents an empty rectangle.
    public static var null: CGRect {
        .init(x: .nan, y: .nan, width: .nan, height: .nan)
    }

    /// A rectangle that represents a zero rectangle.
    /// 
    /// - Note: This rectangle has an origin of (0, 0) and a size of (0, 0).
    public static var zero: CGRect {
        .init(origin: .zero, size: .zero)
    }

    // MARK: - Instance Methods
    
    /// Applies a transformation to the rectangle.
    /// - Parameter t: The transformation to apply.
    /// - Returns: Returns a new rectangle that is the result of applying the transformation to the original rectangle.
    /// - Note: The transformation is applied to the rectangle's origin and size.
    /// Complexity: O(1)
    public func applying(_ t: CGAffineTransform) -> CGRect {
        let origin = CGPoint(x: self.origin.x, y: self.origin.y).applying(t)
        let size = CGSize(width: self.size.width, height: self.size.height).applying(t)
        return CGRect(origin: origin, size: size)
    }

    /// Checks if the rectangle contains a specified point.
    /// - Parameter point: The point to check.
    /// - Returns: A Boolean value indicating whether the rectangle contains the specified point.
    /// - Note: A rectangle contains a point if the point's x-coordinate is greater than or equal to the rectangle's minimum x-coordinate and less than or equal to the rectangle's maximum x-coordinate, and the point's y-coordinate is greater than or equal to the rectangle's minimum y-coordinate and less than or equal to the rectangle's maximum y-coordinate.
    /// Complexity: O(1)
    public func contains(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    /// Checks if the rectangle contains another rectangle.
    /// - Parameter rect: The rectangle to check.
    /// - Returns: A Boolean value indicating whether the rectangle contains the specified rectangle.
    /// - Note: A rectangle contains another rectangle if the other rectangle's origin is within the bounds of the rectangle and the other rectangle's maximum x and y coordinates are also within the bounds of the rectangle.
    /// Complexity: O(1)
    public func contains(_ rect: CGRect) -> Bool {
        contains(rect.origin) && contains(CGPoint(x: rect.maxX, y: rect.maxY))
    }
}