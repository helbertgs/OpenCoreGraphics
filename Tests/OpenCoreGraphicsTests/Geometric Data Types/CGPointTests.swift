import Testing
@testable import OpenCoreGraphics

/// Tests point construction, transformation, and arithmetic.
struct CGPointTests {
    /// Verifies numeric initializers, zero, and affine transformation.
    @Test
    func initializersAndAffineApplication() {
        #expect(CGPoint(x: 2, y: 3) == CGPoint(x: 2.0, y: 3.0))
        #expect(CGPoint(x: Int32(4), y: Int32(5)) == CGPoint(x: 4.0, y: 5.0))
        #expect(CGPoint.zero == CGPoint(x: 0, y: 0))

        let transform = CGAffineTransform(a: 2, b: 0, c: 0, d: 3, tx: 4, ty: 5)
        #expect(CGPoint(x: 1, y: 2).applying(transform) == CGPoint(x: 6, y: 11))
    }

    /// Verifies point arithmetic operators return the expected coordinates.
    @Test
    func arithmeticOperators() {
        let point = CGPoint(x: 8, y: 12)

        #expect(point + CGPoint(x: 2, y: 3) == CGPoint(x: 10, y: 15))
        #expect(point - CGPoint(x: 2, y: 3) == CGPoint(x: 6, y: 9))
        #expect(point * 2 == CGPoint(x: 16, y: 24))
        #expect(2 * point == CGPoint(x: 16, y: 24))
        #expect(point / 2 == CGPoint(x: 4, y: 6))
        #expect(24 / CGPoint(x: 3, y: 4) == CGPoint(x: 8, y: 6))
    }
}
