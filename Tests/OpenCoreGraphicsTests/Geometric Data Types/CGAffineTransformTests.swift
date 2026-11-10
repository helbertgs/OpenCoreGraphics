import Testing
@testable import OpenCoreGraphics

struct CGAffineTransformTests {
    /// Verifies the 2D initializer maps the origin using its translation.
    @Test
    func twoDimensionalInitializerTransformsOrigin() {
        let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 5, ty: 7)

        #expect(CGPoint.zero.applying(transform) == CGPoint(x: 5, y: 7))
    }

    /// Verifies translation helpers expose their values through 2D accessors.
    @Test
    func translationHelpersExposeTranslationComponents() {
        let transform = CGAffineTransform.translate(5, 7)

        #expect(transform.tx == 5)
        #expect(transform.ty == 7)
    }

    /// Verifies each 2D accessor reads and writes its corresponding matrix entry.
    @Test
    func twoDimensionalAccessorsMapToMatrixEntries() {
        var transform = CGAffineTransform.identity
        transform.a = 2
        transform.b = 3
        transform.c = 4
        transform.d = 5
        transform.tx = 6
        transform.ty = 7

        #expect(transform.a == 2)
        #expect(transform.b == 3)
        #expect(transform.c == 4)
        #expect(transform.d == 5)
        #expect(transform.tx == 6)
        #expect(transform.ty == 7)
    }
}
