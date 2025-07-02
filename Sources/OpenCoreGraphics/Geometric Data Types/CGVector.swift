import Foundation

/// A structure that contains a four-dimensional vector.
@frozen
public struct CGVector : Codable, Equatable, Hashable {

    // MARK: - Special Values

    /// A vector with coordinates (0, 0).
    public static let zero: CGVector = CGVector(0)

    // MARK: - Geometric Properties

    /// The x component of the vector.
    public var x: Double

    /// The y component of the vector.
    public var y: Double

    /// The z component of the vector.
    public var z: Double

    /// The w component of the vector.
    public var w: Double

    // MARK: - Initializers

    /// Creates a new vector with the specified x, y, z, and w coordinates.
    /// - Parameter scalar: The scalar value to set all components of the vector.
    @inlinable public init(_ scalar: Double) {
        self.x = scalar
        self.y = scalar
        self.z = scalar
        self.w = scalar
    }

    /// Creates a new vector with the specified x and y coordinates.
    /// - Parameters:
    ///   - x: X coordinate of the vector.
    ///   - y: Y coordinate of the vector.
    ///   - z: Z coordinate of the vector.
    ///   - w: W coordinate of the vector.
    @inlinable public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0, _ w: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    /// Creates a new vector with the specified x and y coordinates.
    /// - Parameters:
    ///   - x: X coordinate of the vector.
    ///   - y: Y coordinate of the vector.
    ///   - z: Z coordinate of the vector.
    ///   - w: W coordinate of the vector.
    /// - Note: This initializer converts the integer values to Double.
    @inlinable public init(_ x: Int = 0, _ y: Int = 0, _ z: Int = 0, _ w: Int = 0) {
        self.x = Double(x)
        self.y = Double(y)
        self.z = Double(z)
        self.w = Double(w)
    }

    /// Creates a new vector with the specified x and y coordinates.
    /// - Parameters:
    ///   - x: X coordinate of the vector.
    ///   - y: Y coordinate of the vector.
    ///   - z: Z coordinate of the vector.
    ///   - w: W coordinate of the vector.
    /// - Note: This initializer converts the integer values to Double.
    @inlinable public init(_ x: Int32 = 0, _ y: Int32 = 0, _ z: Int32 = 0, _ w: Int32 = 0) {
        self.x = Double(x)
        self.y = Double(y)
        self.z = Double(z)
        self.w = Double(w)
    }

    // MARK: - Subscript

    /// Accesses the component at the specified index.
    public subscript(v: Int) -> Double {
        get {
            switch v {
                case 0 : x
                case 1 : y
                case 2 : z
                case 3 : w
                default: fatalError("Index outside of bounds")
            }
        }
        
        set {
            switch v {
                case 0 : x = newValue
                case 1 : y = newValue
                case 2 : z = newValue
                case 3 : w = newValue
                default: fatalError("Index outside of bounds")
            }
        }
    }

    /// The dot product of the vector with another vector.
    /// - Parameter v: The vector to compute the dot product with.
    /// - Returns: The dot product of the two vectors.
    /// - Complexity: O(1)
    @inlinable public func dot(_ v: Self) -> Double {
        return x * v.x + y * v.y + z * v.z + w * v.w
    }

    /// Returns the length of the vector.
    /// - Returns: The length of the vector.
    /// - Note: This method uses the Euclidean length formula.
    /// - Complexity: O(1)
    @inlinable public func length() -> Double {
        return sqrt(x * x + y * y + z * z + w * w)
    }

    /// Returns the squared length of the vector.
    /// - Returns: The squared length of the vector.
    /// - Note: This method is more efficient than `length()` if you only need the squared length.
    /// - Complexity: O(1)
    @inlinable public func lengthSquared() -> Double {
        return x * x + y * y + z * z + w * w
    }

    /// Returns the normalized vector.
    /// - Returns: A new vector with the same direction as the original but with a length of 1.
    /// - Note: This method does not modify the original vector.
    /// - Complexity: O(1)
    @inlinable public func normalized() -> Self {
        let len = length()
        return CGVector(x / len, y / len, z / len, w / len)
    }

    /// Returns the normalized vector.
    /// - Parameters:
    ///   - to: The vector to normalize to.
    ///   - t: The interpolation factor.
    /// - Returns: The normalized vector.
    /// - Note: This method is used to interpolate between two vectors.
    /// - Complexity: O(1)
    @inlinable public func interpolated(_ to: Self, by t: Double) -> Self {
        self + (to - self) * t
    }

    /// Returns the distance to another vector.
    /// - Parameter to: The vector to compute the distance to.
    /// - Returns: The distance between the two vectors.
    /// - Note: This method uses the Euclidean distance formula.
    /// - Complexity: O(1)
    @inlinable public func distance(to: Self) -> Double {
        return sqrt((x - to.x) * (x - to.x) +
                    (y - to.y) * (y - to.y) +
                    (z - to.z) * (z - to.z) +
                    (w - to.w) * (w - to.w))
    }

    /// Returns a new vector that is the result of adding two vectors.
    /// - Parameters:
    ///   - lhs: The left-hand side vector.
    ///   - rhs: The right-hand side vector.
    /// - Returns: A new vector that is the sum of the two vectors.
    /// - Complexity: O(1) 
    @inlinable public static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z, lhs.w + rhs.w)
    }

    /// Returns a new vector that is the result of subtracting two vectors.
    /// - Parameters:
    ///   - lhs: The left-hand side vector.
    ///   - rhs: The right-hand side vector.
    /// - Returns: A new vector that is the difference of the two vectors.
    /// - Complexity: O(1)
    @inlinable public static func - (lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z, lhs.w - rhs.w)
    }

    /// Returns a new vector that is the result of multiplying two vectors.
    /// - Parameters:
    ///   - lhs: The left-hand side vector.
    ///   - rhs: The right-hand side vector.
    /// - Returns: A new vector that is the product of the two vectors.
    /// - Complexity: O(1)
    @inlinable public static func * (lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(lhs.x * rhs.x, lhs.y * rhs.y, lhs.z * rhs.z, lhs.w * rhs.w)
    }

    /// Returns a new vector that is the result of dividing two vectors.
    /// - Parameters:
    ///   - lhs: The left-hand side vector.
    ///   - rhs: The right-hand side vector.
    /// - Returns: A new vector that is the quotient of the two vectors.
    /// - Complexity: O(1)
    @inlinable public static func / (lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(lhs.x / rhs.x, lhs.y / rhs.y, lhs.z / rhs.z, lhs.w / rhs.w)
    }

    /// Returns a new vector that is the result of multiplying a vector by a scalar.
    /// - Parameters:
    ///   - lhs: The vector to multiply.
    ///   - rhs: The scalar to multiply by.
    /// - Returns: A new vector that is the product of the vector and the scalar.
    /// - Complexity: O(1)
    @inlinable public static func * (lhs: CGVector, rhs: Double) -> CGVector {
        return CGVector(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs, lhs.w * rhs)
    }

    /// Returns a new vector that is the result of dividing a vector by a scalar.
    /// - Parameters:
    ///   - lhs: The vector to divide.
    ///   - rhs: The scalar to divide by.
    /// - Returns: A new vector that is the quotient of the vector and the scalar.
    /// - Complexity: O(1)
    @inlinable public static func / (lhs: CGVector, rhs: Double) -> CGVector {
        return CGVector(lhs.x / rhs, lhs.y / rhs, lhs.z / rhs, lhs.w / rhs)
    }

    /// Returns a new vector that is the result of adding two vectors.
    /// - Parameters:
    ///   - lhs: The left-hand side vector.
    ///   - rhs: The right-hand side vector.
    /// - Returns: A new vector that is the sum of the two vectors.
    /// - Complexity: O(1) 
    @inlinable public static func += (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs + rhs
    }

    /// Returns a new vector that is the result of subtracting two vectors.
    /// - Parameters:
    ///   - lhs: The left-hand side vector.
    ///   - rhs: The right-hand side vector.
    /// - Returns: A new vector that is the difference of the two vectors.
    /// - Complexity: O(1)
    @inlinable public static func -= (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs - rhs
    }

    /// Returns a new vector that is the result of multiplying two vectors.
    /// - Parameters:
    ///   - lhs: The left-hand side vector.
    ///   - rhs: The right-hand side vector.
    /// - Returns: A new vector that is the product of the two vectors.
    /// - Complexity: O(1)
    @inlinable public static func *= (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs * rhs
    }

    /// Returns a new vector that is the result of dividing two vectors.
    /// - Parameters:
    ///   - lhs: The left-hand side vector.
    ///   - rhs: The right-hand side vector.
    /// - Returns: A new vector that is the quotient of the two vectors.
    /// - Complexity: O(1)
    @inlinable public static func /= (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs / rhs
    }

    /// Returns a new vector that is the result of multiplying a vector by a matrix.
    /// - Parameters:
    ///  - lhs: The vector to multiply.
    ///  - rhs: The matrix to multiply by.
    /// - Returns: A new vector that is the product of the vector and the matrix.
    /// - Complexity: O(1)
    public static func * (lhs: CGVector, rhs: CGAffineTransform) -> CGVector {
        .init(
            lhs.x * rhs.m11 + lhs.y * rhs.m12 + lhs.z * rhs.m13 + lhs.w * rhs.m14,
            lhs.x * rhs.m21 + lhs.y * rhs.m22 + lhs.z * rhs.m23 + lhs.w * rhs.m24,
            lhs.x * rhs.m31 + lhs.y * rhs.m32 + lhs.z * rhs.m33 + lhs.w * rhs.m34,
            lhs.x * rhs.m41 + lhs.y * rhs.m42 + lhs.z * rhs.m43 + lhs.w * rhs.m44
        )
    }
}