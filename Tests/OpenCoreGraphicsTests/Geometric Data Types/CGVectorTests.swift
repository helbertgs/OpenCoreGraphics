import Testing
@testable import OpenCoreGraphics

/// Tests vector construction, metrics, interpolation, and arithmetic.
struct CGVectorTests {
    /// Verifies vector initializers, zero, and indexed component access.
    @Test
    func initializersAndSubscript() {
        #expect(CGVector.zero == CGVector(0))
        #expect(CGVector(1, 2, 3, 4) == CGVector(1.0, 2.0, 3.0, 4.0))
        #expect(CGVector(Int32(1), Int32(2), Int32(3), Int32(4)) == CGVector(1, 2, 3, 4))

        var vector = CGVector(1, 2, 3, 4)
        #expect(vector[0] == 1)
        #expect(vector[1] == 2)
        #expect(vector[2] == 3)
        #expect(vector[3] == 4)
        vector[0] = 5
        vector[1] = 6
        vector[2] = 7
        vector[3] = 8
        #expect(vector == CGVector(5, 6, 7, 8))
    }

    /// Verifies vector metrics and interpolation helpers.
    @Test
    func metricsAndInterpolation() {
        let vector = CGVector(1, 2, 2, 0)
        let destination = CGVector(4, 5, 2, 0)

        #expect(vector.dot(destination) == 18)
        #expect(vector.length() == 3)
        #expect(vector.lengthSquared() == 9)
        #expect(vector.normalized() == CGVector(1.0 / 3, 2.0 / 3, 2.0 / 3, 0))
        #expect(vector.interpolated(destination, by: 0.5) == CGVector(2.5, 3.5, 2, 0))
        #expect(vector.distance(to: destination) == 4.242640687119285)
    }

    /// Verifies vector arithmetic and compound assignment operators.
    @Test
    func arithmeticOperators() {
        let lhs = CGVector(8, 12, 16, 20)
        let rhs = CGVector(2, 3, 4, 5)

        #expect(lhs + rhs == CGVector(10, 15, 20, 25))
        #expect(lhs - rhs == CGVector(6, 9, 12, 15))
        #expect(lhs * rhs == CGVector(16, 36, 64, 100))
        #expect(lhs / rhs == CGVector(4, 4, 4, 4))
        #expect(lhs * 2 == CGVector(16, 24, 32, 40))
        #expect(lhs / 2 == CGVector(4, 6, 8, 10))

        var combined = rhs
        combined += rhs
        combined -= rhs
        combined *= rhs
        combined /= rhs
        #expect(combined == rhs)
        #expect(CGVector(1, 2, 3, 4) * CGAffineTransform.identity == CGVector(1, 2, 3, 4))
    }
}
