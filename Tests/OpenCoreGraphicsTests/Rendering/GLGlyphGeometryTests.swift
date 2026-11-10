import Foundation
import Testing
@testable import OpenCoreGraphics

/// Checks the documented asymmetric glyph quad independently of a graphics context.
struct GLGlyphGeometryTests {
    /// Verifies all six UVs and the transformed vertices, including text-space spacing.
    @Test
    private func mapsDocumentedMaskAndTransforms() throws {
        let bitmap = CGGlyphBitmap(
            width: 2, height: 3, xOffset: 1, yOffset: -3,
            coverage: Data([255, 32, 64, 192, 128, 0])
        )
        let atlas = try #require(CGGlyphAtlas(bitmaps: [bitmap]))
        let vertices = GLRendererGeometry.glyphVertices(
            [1], positions: [CGPoint(x: 10, y: 10)], glyphAtlas: atlas,
            characterSpacing: 0, textMatrix: .identity, textPosition: .zero, ctm: .identity
        )
        #expect(vertices.map(\.positionX) == [11, 13, 13, 11, 13, 11])
        #expect(vertices.map(\.positionY) == [10, 10, 13, 10, 13, 13])
        #expect(vertices.map(\.textureX) == [0.2, 0.6, 0.6, 0.2, 0.6, 0.2])
        #expect(vertices.map(\.textureY) == [0.8, 0.8, 0.2, 0.8, 0.2, 0.2])

        let transformed = GLRendererGeometry.glyphVertices(
            [1], positions: [CGPoint(x: 2, y: 3)], glyphAtlas: atlas,
            characterSpacing: 0,
            textMatrix: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0),
            textPosition: CGPoint(x: 10, y: 20),
            ctm: CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 5, ty: 7)
        )
        #expect(transformed.map(\.positionX) == [19, 19, 13, 19, 13, 13])
        #expect(transformed.map(\.positionY) == [53, 57, 57, 53, 57, 53])

        let pair = GLRendererGeometry.glyphVertices(
            [1, 1], positions: [CGPoint(x: 2, y: 3), CGPoint(x: 8, y: 3)],
            glyphAtlas: try #require(CGGlyphAtlas(bitmaps: [bitmap, bitmap])),
            characterSpacing: 3,
            textMatrix: CGAffineTransform(a: 2, b: 0, c: 0, d: 1, tx: 0, ty: 0),
            textPosition: .zero, ctm: .identity
        )
        try #require(pair.count == 12)
        #expect(pair[6].positionX - pair[0].positionX == 18)
    }
}
