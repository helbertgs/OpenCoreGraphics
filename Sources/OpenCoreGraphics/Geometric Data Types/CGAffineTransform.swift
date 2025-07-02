import Foundation

/// An affine transformation matrix for use in drawing 2D graphics.
public struct CGAffineTransform: Codable, CustomStringConvertible, Equatable, Hashable, Sendable {

    // MARK: - Instance Properties

    /// The entry at position [1,1] in the matrix.
    internal var m11: Double = 0.0

    /// The entry at position [1,2] in the matrix.
    internal var m12: Double = 0.0

    /// The entry at position [1,3] in the matrix.
    internal var m13: Double = 0.0

    /// The entry at position [1,4] in the matrix.
    internal var m14: Double = 0.0

    /// The entry at position [2,1] in the matrix.
    internal var m21: Double = 0.0

    /// The entry at position [2,2] in the matrix.
    internal var m22: Double = 0.0

    /// The entry at position [2,3] in the matrix.
    internal var m23: Double = 0.0

    /// The entry at position [2,4] in the matrix.
    internal var m24: Double = 0.0

    /// The entry at position [3,1] in the matrix.
    internal var m31: Double = 0.0

    /// The entry at position [3,2] in the matrix.
    internal var m32: Double = 0.0

    /// The entry at position [3,3] in the matrix.
    internal var m33: Double = 0.0

    /// The entry at position [3,4] in the matrix.
    internal var m34: Double = 0.0

    /// The entry at position [4,1] in the matrix.
    internal var m41: Double = 0.0

    /// The entry at position [4,2] in the matrix.
    internal var m42: Double = 0.0

    /// The entry at position [4,3] in the matrix.
    internal var m43: Double = 0.0

    /// The entry at position [4,4] in the matrix.
    internal var m44: Double = 0.0

    // MARK: - Initializers

    /// Initializes a new affine transform with the zero values.
    public init() { }

    /// Initializes a new affine transform with the specified vector.
    /// - Parameters:
    ///     - v: The vector to initialize the transform with.
    public init(_ v: CGVector) {
        m11 = v[0]
        m22 = v[1]
        m33 = v[2]
        m44 = v[3]
    }

    /// Initializes a new affine transform with the specified value.
    /// - Parameters:
    ///     - v: The value to initialize the transform with.
    public init(_ v: Double) {
        m11 = v
        m22 = v
        m33 = v
        m44 = v
    }

    /// Initializes a new affine transform with the specified columns.
    /// - Parameters:
    ///   - c0: A vector representing the first column of the matrix.
    ///   - c1: A vector representing the second column of the matrix.
    ///   - c2: A vector representing the third column of the matrix.
    ///   - c3: A vector representing the fourth column of the matrix.
    public init(_ c0: CGVector, _ c1: CGVector, _ c2: CGVector, _ c3: CGVector) {
        (m11, m12, m13, m14) = (c0[0], c0[1], c0[2], c0[3])
        (m21, m22, m23, m24) = (c1[0], c1[1], c1[2], c1[3])
        (m31, m32, m33, m34) = (c2[0], c2[1], c2[2], c2[3])
        (m41, m42, m43, m44) = (c3[0], c3[1], c3[2], c3[3])
    }

    
    public init(_ p: CGPoint) {
        (m11, m12, m13, m14) = (1,     0, 0, 0) 
        (m21, m22, m23, m24) = (0,     1, 0, 0)
        (m31, m32, m33, m34) = (0,     0, 1, 0)
        (m41, m42, m43, m44) = (p.x, p.y, 0, 1)
    }

    public init(_ s: CGSize) {
        (m11, m12, m13, m14) = (s.width,    0,        0, 0) 
        (m21, m22, m23, m24) = (0,          s.height, 0, 0)
        (m31, m32, m33, m34) = (0,          0,        1, 0)
        (m41, m42, m43, m44) = (0,          0,        0, 1)
    }

    public init (_ r: CGRect) {
        (m11, m12, m13, m14) = (r.width,    0,        0, 0) 
        (m21, m22, m23, m24) = (0,          r.height, 0, 0)
        (m31, m32, m33, m34) = (0,          0,        1, 0)
        (m41, m42, m43, m44) = (r.minX,     r.minY,   0, 1)
    }

    // MARK: - Type Properties

    /// The identity transform.
    /// - Returns: A new affine transform that is the identity transform.
    /// - Complexity: O(1)
    public static var identity: Self {
        .init(1)
    }

    /// Transposes the affine transform.
    /// - Returns: A new affine transform that is the transpose of the original.
    /// - Complexity: O(1)
    public var transposed: Self {
        .init(
            .init(m11, m21, m31, m41),
            .init(m12, m22, m32, m42),
            .init(m13, m23, m33, m43),
            .init(m14, m24, m34, m44)
        )
    }

    /// The determinant of the affine transform.
    /// - Returns: The determinant of the affine transform.
    /// - Complexity: O(1)
    public var inverse: Self {
        let det = m11 * (m22 * m33 - m23 * m32) - m12 * (m21 * m33 - m23 * m31) + m13 * (m21 * m32 - m22 * m31)
        guard det != 0 else { return .identity }
        
        let invDet = 1 / det
        
        return .init(
            .init((m22 * m33 - m23 * m32) * invDet, (m13 * m32 - m12 * m33) * invDet, (m12 * m23 - m13 * m22) * invDet, 0),
            .init((m13 * m32 - m12 * m33) * invDet, (m11 * m33 - m13 * m31) * invDet, (m13 * m21 - m11 * m23) * invDet, 0),
            .init((m12 * m23 - m13 * m22) * invDet, (m12 * m21 - m11 * m22) * invDet, (m11 * m22 - m12 * m21) * invDet, 0),
            .init(0, 0, 0, 1)
        )
    }

    // MARK: - Subscript

    /// Accesses the specified column.
    /// - Parameter col: The column index (0 to 3).
    /// - Returns: The vector representing the specified column.
    /// - Complexity: O(1)
    public subscript(col: Int) -> CGVector {
        get {
            switch col {
            case 0: .init(m11, m12, m13, m14)
            case 1: .init(m21, m22, m23, m24)
            case 2: .init(m31, m32, m33, m34)
            case 3: .init(m41, m42, m43, m44)
            default: fatalError("Index outside of bounds")
            }
        }
        
        set {
            switch col {
            case 0: m11 = newValue[0]; m12 = newValue[1]; m12 = newValue[2]; m12 = newValue[3];
            case 1: m21 = newValue[0]; m22 = newValue[1]; m22 = newValue[2]; m22 = newValue[3];
            case 2: m31 = newValue[0]; m32 = newValue[1]; m32 = newValue[2]; m32 = newValue[3];
            case 3: m41 = newValue[0]; m42 = newValue[1]; m42 = newValue[2]; m42 = newValue[3];
            default: fatalError("Index outside of bounds")
            }
        }
    }

    /// Accesses the specified row and column.
    /// - Parameters:
    ///   - col: The column index (0 to 3).
    ///   - row: The row index (0 to 3).
    /// - Returns: The value at the specified row and column.
    /// - Complexity: O(1)
    public subscript(col: Int, row: Int) -> Double {
        get {
            switch col {
            case 0:
                switch row {
                case 0: return m11
                case 1: return m12
                case 2: return m13
                case 3: return m14
                default: fatalError("Index outside of bounds")
                }
            case 1:
                switch row {
                case 0: return m21
                case 1: return m22
                case 2: return m23
                case 3: return m24
                default: fatalError("Index outside of bounds")
                }
            case 2:
                switch row {
                case 0: return m31
                case 1: return m32
                case 2: return m33
                case 3: return m34
                default: fatalError("Index outside of bounds")
                }
            case 3:
                switch row {
                case 0: return m41
                case 1: return m42
                case 2: return m43
                case 3: return m44
                default: fatalError("Index outside of bounds")
                }
            default: fatalError("Index outside of bounds")
            }
        }
        
        set {
            switch col {
            case 0:
                switch row {
                case 0: m11 = newValue
                case 1: m12 = newValue
                case 2: m13 = newValue
                case 3: m14 = newValue
                default: fatalError("Index outside of bounds")
                }
            case 1:
                switch row {
                case 0: m21 = newValue
                case 1: m22 = newValue
                case 2: m23 = newValue
                case 3: m24 = newValue
                default: fatalError("Index outside of bounds")
                }
            case 2:
                switch row {
                case 0: m31 = newValue
                case 1: m32 = newValue
                case 2: m33 = newValue
                case 3: m34 = newValue
                default: fatalError("Index outside of bounds")
                }
            case 3:
                switch row {
                case 0: m41 = newValue
                case 1: m42 = newValue
                case 2: m43 = newValue
                case 3: m44 = newValue
                default: fatalError("Index outside of bounds")
                }
            default: fatalError("Index outside of bounds")
            }
        }
    }

    // MARK: - Matrix Operations

    /// Multiplies the affine transform by a scalar value.
    /// - Parameters:
    ///   - lhs: The affine transform to multiply.
    ///   - rhs: The scalar value to multiply by.
    /// - Returns: A new affine transform that is the result of the multiplication.
    /// - Complexity: O(1)
    public static func * (_ lhs: Self, _ rhs: Double) -> Self {
        .init(
            .init(lhs.m11 * rhs, lhs.m12 * rhs, lhs.m13 * rhs, lhs.m14 * rhs),
            .init(lhs.m21 * rhs, lhs.m22 * rhs, lhs.m23 * rhs, lhs.m24 * rhs),
            .init(lhs.m31 * rhs, lhs.m32 * rhs, lhs.m33 * rhs, lhs.m34 * rhs),
            .init(lhs.m41 * rhs, lhs.m42 * rhs, lhs.m43 * rhs, lhs.m44 * rhs)
        )
    }

    /// Multiplies two affine transforms together.
    /// - Parameters:
    ///   - lhs: The left-hand side affine transform.
    ///   - rhs: The right-hand side affine transform.
    /// - Returns: A new affine transform that is the result of the multiplication.
    /// - Complexity: O(1)
    public static func * (_ lhs: Self, _ rhs: Self) -> Self {
        var m = Self.identity
        
        m.m11 = lhs.m11 * rhs.m11 + lhs.m21 * rhs.m12
        m.m11 += lhs.m31 * rhs.m13 + lhs.m41 * rhs.m14
        
        m.m12 = lhs.m12 * rhs.m11 + lhs.m22 * rhs.m12
        m.m12 += lhs.m32 * rhs.m13 + lhs.m42 * rhs.m14
        
        m.m13 = lhs.m13 * rhs.m11 + lhs.m23 * rhs.m12
        m.m13 += lhs.m33 * rhs.m13 + lhs.m43 * rhs.m14
        
        m.m14 = lhs.m14 * rhs.m11 + lhs.m24 * rhs.m12
        m.m14 += lhs.m34 * rhs.m13 + lhs.m44 * rhs.m14
        
        m.m21 = lhs.m11 * rhs.m21 + lhs.m21 * rhs.m22
        m.m21 += lhs.m31 * rhs.m23 + lhs.m41 * rhs.m24
        
        m.m22 = lhs.m12 * rhs.m21 + lhs.m22 * rhs.m22
        m.m22 += lhs.m32 * rhs.m23 + lhs.m42 * rhs.m24
        
        m.m23 = lhs.m13 * rhs.m21 + lhs.m23 * rhs.m22
        m.m23 += lhs.m33 * rhs.m23 + lhs.m43 * rhs.m24
        
        m.m24 = lhs.m14 * rhs.m21 + lhs.m24 * rhs.m22
        m.m24 += lhs.m34 * rhs.m23 + lhs.m44 * rhs.m24
        
        m.m31 = lhs.m11 * rhs.m31 + lhs.m21 * rhs.m32
        m.m31 += lhs.m31 * rhs.m33 + lhs.m41 * rhs.m34
        
        m.m32 = lhs.m12 * rhs.m31 + lhs.m22 * rhs.m32
        m.m32 += lhs.m32 * rhs.m33 + lhs.m42 * rhs.m34
        
        m.m33 = lhs.m13 * rhs.m31 + lhs.m23 * rhs.m32
        m.m33 += lhs.m33 * rhs.m33 + lhs.m43 * rhs.m34
        
        m.m34 = lhs.m14 * rhs.m31 + lhs.m24 * rhs.m32
        m.m34 += lhs.m34 * rhs.m33 + lhs.m44 * rhs.m34
        
        m.m41 = lhs.m11 * rhs.m41 + lhs.m21 * rhs.m42
        m.m41 += lhs.m31 * rhs.m43 + lhs.m41 * rhs.m44
        
        m.m42 = lhs.m12 * rhs.m41 + lhs.m22 * rhs.m42
        m.m42 += lhs.m32 * rhs.m43 + lhs.m42 * rhs.m44
        
        m.m43 = lhs.m13 * rhs.m41 + lhs.m23 * rhs.m42
        m.m43 += lhs.m33 * rhs.m43 + lhs.m43 * rhs.m44
        
        m.m44 = lhs.m14 * rhs.m41 + lhs.m24 * rhs.m42
        m.m44 += lhs.m34 * rhs.m43 + lhs.m44 * rhs.m44

        return m
    }

    /// Multiplies the affine transform by a vector.
    /// - Parameters:
    ///   - lhs: The affine transform to multiply.
    ///   - rhs: The vector to multiply by.
    /// - Returns: A new affine transform that is the result of the multiplication.
    /// - Complexity: O(1)
    public static func * (lhs: Self, rhs: CGVector) -> CGVector {
        .init(
            rhs.x * lhs.m11 + rhs.y * lhs.m21 + rhs.z * lhs.m31 + rhs.w * lhs.m41,
            rhs.x * lhs.m12 + rhs.y * lhs.m22 + rhs.z * lhs.m32 + rhs.w * lhs.m42,
            rhs.x * lhs.m13 + rhs.y * lhs.m23 + rhs.z * lhs.m33 + rhs.w * lhs.m43,
            rhs.x * lhs.m14 + rhs.y * lhs.m24 + rhs.z * lhs.m34 + rhs.w * lhs.m44
        )
    }

    /// Divides the affine transform by a scalar value.
    /// - Parameters:
    ///   - lhs: The affine transform to divide.
    ///   - rhs: The scalar value to divide by.
    /// - Returns: A new affine transform that is the result of the division.
    /// - Complexity: O(1)
    public static func / (_ lhs: Self, _ rhs: Double) -> Self {
        .init(
            .init(lhs.m11 / rhs, lhs.m12 / rhs, lhs.m13 / rhs, lhs.m14 / rhs),
            .init(lhs.m21 / rhs, lhs.m22 / rhs, lhs.m23 / rhs, lhs.m24 / rhs),
            .init(lhs.m31 / rhs, lhs.m32 / rhs, lhs.m33 / rhs, lhs.m34 / rhs),
            .init(lhs.m41 / rhs, lhs.m42 / rhs, lhs.m43 / rhs, lhs.m44 / rhs)
        )
    }

    /// Adds two affine transforms together.
    /// - Parameters:
    ///   - lhs: The left-hand side affine transform.
    ///   - rhs: The right-hand side affine transform.
    /// - Returns: A new affine transform that is the sum of the two transforms.
    /// - Complexity: O(1)
    public static func + (_ lhs: Self, _ rhs: Self) -> Self {
        .init(
            .init(lhs.m11 + rhs.m11, lhs.m12 + rhs.m12, lhs.m13 + rhs.m13, lhs.m14 + rhs.m14),
            .init(lhs.m21 + rhs.m21, lhs.m22 + rhs.m22, lhs.m23 + rhs.m23, lhs.m24 + rhs.m24),
            .init(lhs.m31 + rhs.m31, lhs.m32 + rhs.m32, lhs.m33 + rhs.m33, lhs.m34 + rhs.m34),
            .init(lhs.m41 + rhs.m41, lhs.m42 + rhs.m42, lhs.m43 + rhs.m43, lhs.m44 + rhs.m44)
        )
    }

    /// Subtracts one affine transform from another.
    /// - Parameters:
    ///   - lhs: The left-hand side affine transform.
    ///   - rhs: The right-hand side affine transform.
    /// - Returns: A new affine transform that is the difference of the two transforms.
    /// - Complexity: O(1)
    public static func - (_ lhs: Self, _ rhs: Self) -> Self {
        .init(
            .init(lhs.m11 - rhs.m11, lhs.m12 - rhs.m12, lhs.m13 - rhs.m13, lhs.m14 - rhs.m14),
            .init(lhs.m21 - rhs.m21, lhs.m22 - rhs.m22, lhs.m23 - rhs.m23, lhs.m24 - rhs.m24),
            .init(lhs.m31 - rhs.m31, lhs.m32 - rhs.m32, lhs.m33 - rhs.m33, lhs.m34 - rhs.m34),
            .init(lhs.m41 - rhs.m41, lhs.m42 - rhs.m42, lhs.m43 - rhs.m43, lhs.m44 - rhs.m44)
        )
    }

    /// Checks if two affine transforms are equal.
    /// - Parameters:
    ///   - lhs: The left-hand side affine transform.
    ///   - rhs: The right-hand side affine transform.
    /// - Returns: `true` if the transforms are equal, `false` otherwise.
    /// - Complexity: O(1) 
    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.m11 == rhs.m11 &&
        lhs.m12 == rhs.m12 &&
        lhs.m13 == rhs.m13 &&
        lhs.m14 == rhs.m14 &&
        lhs.m21 == rhs.m21 &&
        lhs.m22 == rhs.m22 &&
        lhs.m23 == rhs.m23 &&
        lhs.m24 == rhs.m24 &&
        lhs.m31 == rhs.m31 &&
        lhs.m32 == rhs.m32 &&
        lhs.m33 == rhs.m33 &&
        lhs.m34 == rhs.m34 &&
        lhs.m41 == rhs.m41 &&
        lhs.m42 == rhs.m42 &&
        lhs.m43 == rhs.m43 &&
        lhs.m44 == rhs.m44
    }

    // MARK: - Transform Operations

    /// Creates a scaling transform.
    /// - Parameters:
    ///   - x: The scaling factor in the x direction.
    ///   - y: The scaling factor in the y direction.
    ///   - z: The scaling factor in the z direction.
    /// - Returns: A new affine transform representing the scaling.
    /// - Complexity: O(1)
    public static func scale(_ x: Double, _ y: Double, _ z: Double = 1) -> Self {
        .init(
            .init(x, 0, 0, 0),
            .init(0, y, 0, 0),
            .init(0, 0, z, 0),
            .init(0, 0, 0, 1)
        )
    }

    /// Scales the affine transform by the specified factors.
    /// - Parameters:
    ///   - x: The scaling factor in the x direction.
    ///   - y: The scaling factor in the y direction.
    ///   - z: The scaling factor in the z direction.
    /// - Returns: A new affine transform representing the scaling.
    /// - Complexity: O(1)
    public func scaledBy(x: Double, y: Double, z: Double = 1) -> Self {
        self * Self.scale(x, y, z)
    }
    
    /// Creates a translation transform.
    /// - Parameters:
    ///   - x: The translation in the x direction.
    ///   - y: The translation in the y direction.
    ///   - z: The translation in the z direction.
    /// - Returns: A new affine transform representing the translation.
    /// - Complexity: O(1)
    public static func translate(_ x: Double, _ y: Double, _ z: Double = 0) -> Self {
        .init(
            .init(1, 0, 0, 0),
            .init(0, 1, 0, 0),
            .init(0, 0, 1, 0),
            .init(x, y, z, 1)
        )
    }

    /// Translates the affine transform by the specified amounts.
    /// - Parameters:
    ///   - x: The translation in the x direction.
    ///   - y: The translation in the y direction.
    ///   - z: The translation in the z direction.
    /// - Returns: A new affine transform representing the translation.
    /// - Complexity: O(1)
    public func translatedBy(x: Double, y: Double, z: Double = 0) -> Self {
        self * Self.translate(x, y, z)
    }
    
    /// Creates a rotation transform.
    /// - Parameters:
    ///   - z: The angle of rotation in radians.
    /// - Returns: A new affine transform representing the rotation.
    /// - Complexity: O(1)
    /// - Note: The rotation is around the z-axis.
    public static func rotate(_ z: Double) -> Self {
        let cz = cos(z)
        let sz = sin(z)
        
        return .init(
            .init(cz, -sz, 0, 0),
            .init(sz,  cz, 0, 0),
            .init(0,    0, 1, 0),
            .init(0,    0, 0, 1)
        )
    }

    /// Rotates the affine transform by the specified angle.
    /// - Parameters:
    ///   - z: The angle of rotation in radians.
    /// - Returns: A new affine transform representing the rotation.
    /// - Complexity: O(1)
    /// - Note: The rotation is around the z-axis.
    public func rotated(by z: Double) -> Self {
        self * Self.rotate(z)
    }

    /// Concatenates the affine transform with another transform.
    /// - Parameter transform: The transform to concatenate with.
    /// - Returns: A new affine transform that is the result of the concatenation.
    /// - Complexity: O(1)
    public func concatenating(_ transform: Self) -> Self {
        self * transform
    }

    // MARK: - Projections

    /// Creates an orthographic projection matrix.
    /// - Parameters:
    ///   - left: The left coordinate of the near clipping plane.
    ///   - right: The right coordinate of the near clipping plane.
    ///   - bottom: The bottom coordinate of the near clipping plane.
    ///   - top: The top coordinate of the near clipping plane.
    ///   - near: The distance to the near clipping plane.
    ///   - far: The distance to the far clipping plane.
    /// - Returns: A new affine transform representing the orthographic projection.
    /// - Complexity: O(1)
    public static func orthographic(_ left: Double, _ right: Double, _ bottom: Double, _ top: Double, _ near: Double, _ far: Double) -> Self {
        var t = Self.identity
        t.m11 = 2 / (right - left)
        t.m14 = -(right + left) / (right - left)
        t.m22 = 2 / (top - bottom)
        t.m24 = -(top + bottom) / (top - bottom)
        t.m33 = -2 / (far - near)
        t.m34 = -(far + near) / (far - near)
        t.m44 = 1
        
        return t
    }

    /// Creates a perspective projection matrix.
    /// - Parameters:
    ///   - fov: The field of view angle in radians.
    ///   - aspect: The aspect ratio of the viewport.
    ///   - near: The distance to the near clipping plane.
    ///   - far: The distance to the far clipping plane.
    /// - Returns: A new affine transform representing the perspective projection.
    /// - Complexity: O(1)
    public static func perspective(_ fov: Double, _ aspect: Double, _ near: Double, _ far: Double) -> Self {
        let f = 1 / tan(fov / 2)
        let depth = far - near

        return .init(
            .init(f / aspect, 0, 0, 0),
            .init(0, f, 0, 0),
            .init(0, 0, (far + near) / depth, -1),
            .init(0, 0, (2 * far * near) / depth, 0)
        )
    }

    // MARK: - CustomStringConvertible

    /// A textual representation of the matrix.
    public var description: String {
    """
    \(Self.self)(
        \(m11), \(m12), \(m13), \(m14),
        \(m21), \(m22), \(m23), \(m24),
        \(m31), \(m32), \(m33), \(m34),
        \(m41), \(m42), \(m43), \(m44)
    )
    """
    }
}
