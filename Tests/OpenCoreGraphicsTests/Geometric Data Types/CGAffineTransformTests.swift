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

    /// Verifies matrix initializers, subscripts, and arithmetic operations.
    @Test
    func matrixInitializersSubscriptsAndArithmetic() {
        let diagonal = CGAffineTransform(CGVector(2, 3, 4, 5))
        #expect(diagonal[0, 0] == 2)
        #expect(diagonal[1, 1] == 3)
        #expect(diagonal[2, 2] == 4)
        #expect(diagonal[3, 3] == 5)
        let uniform = CGAffineTransform(2.0)
        #expect(uniform[0, 0] == 2)
        #expect(uniform[1, 1] == 2)
        #expect(uniform[2, 2] == 2)
        #expect(uniform[3, 3] == 2)

        let columns = CGAffineTransform(
            CGVector(1, 2, 3, 4),
            CGVector(5, 6, 7, 8),
            CGVector(9, 10, 11, 12),
            CGVector(13, 14, 15, 16)
        )
        #expect(columns[0] == CGVector(1, 2, 3, 4))
        #expect(columns[1] == CGVector(5, 6, 7, 8))
        #expect(columns[2] == CGVector(9, 10, 11, 12))
        #expect(columns[3] == CGVector(13, 14, 15, 16))
        #expect(CGAffineTransform(CGPoint(x: 2, y: 3)).tx == 2)
        #expect(CGAffineTransform(CGSize(width: 2, height: 3)).a == 2)
        #expect(CGAffineTransform(CGRect(x: 2, y: 3, width: 4, height: 5)).ty == 3)

        var matrix = CGAffineTransform.identity
        for column in 0..<4 {
            for row in 0..<4 {
                let value = Double(column * 4 + row)
                matrix[column, row] = value
                #expect(matrix[column, row] == value)
            }
        }

        for column in 0..<4 {
            let vector = CGVector(Double(column), 2, 3, 4)
            matrix[column] = vector
            #expect(matrix[column] == vector)
        }

        let identity = CGAffineTransform.identity
        let translation = CGAffineTransform.translate(3, 5)
        let scaledTranslation = translation * 2
        #expect(identity.transposed == identity)
        #expect(CGAffineTransform().inverse == identity)
        #expect(translation * identity == translation)
        #expect(scaledTranslation.tx == 6)
        #expect(scaledTranslation.ty == 10)
        #expect(scaledTranslation[2, 2] == 2)
        #expect(scaledTranslation[3, 3] == 2)
        #expect((translation + identity) - identity == translation)
        #expect(translation / 2 == translation * 0.5)
        #expect(translation * CGVector(1, 2, 0, 1) == CGVector(4, 7, 0, 1))
    }

    /// Verifies scaling, translation, rotation, concatenation, and projections.
    @Test
    func transformOperationsAndProjections() {
        let identity = CGAffineTransform.identity
        let scaling = CGAffineTransform.scale(2, 3)
        let translation = CGAffineTransform.translate(5, 7)
        let rotation = CGAffineTransform.rotate(.pi / 2)

        #expect(identity.scaledBy(x: 2, y: 3) == scaling)
        #expect(identity.translatedBy(x: 5, y: 7) == translation)
        #expect(identity.rotated(by: .pi / 2) == rotation)
        #expect(identity.concatenating(translation) == translation)
        #expect(CGAffineTransform.orthographic(-1, 1, -1, 1, -1, 1) != identity)
        #expect(CGAffineTransform.perspective(.pi / 2, 1, 1, 100) != identity)
        #expect(translation.description.contains("5.0, 7.0"))
    }
}
