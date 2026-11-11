import Foundation
import Testing
@testable import OpenCoreGraphics

/// Verifies bounded glyph atlas pages preserve bitmap data and original text order.
struct GLGlyphAtlasPaginationTests {
    /// Splits repeated glyphs at a small simulated limit without changing positions or order.
    @Test
    func pagesPreserveRepeatedGlyphsAndPositions() throws {
        let bitmap = CGGlyphBitmap(
            width: 2,
            height: 2,
            xOffset: 1,
            yOffset: -2,
            coverage: Data([255, 32, 64, 128])
        )
        let atlas = try #require(CGGlyphAtlas(bitmaps: [bitmap, nil, bitmap, bitmap]))
        let pages = try atlas.pages(maxTextureSize: 11)
        let originalGlyphs: [CGGlyph] = [4, 9, 4, 4]
        let originalPositions = [
            OpenCoreGraphics.CGPoint(x: 0, y: 8),
            OpenCoreGraphics.CGPoint(x: 6, y: 8),
            OpenCoreGraphics.CGPoint(x: 12, y: 8),
            OpenCoreGraphics.CGPoint(x: 18, y: 8)
        ]
        let expected = GLRendererGeometry.glyphVertices(
            originalGlyphs,
            positions: originalPositions,
            glyphAtlas: atlas,
            characterSpacing: 2,
            textMatrix: .identity,
            textPosition: .zero,
            ctm: .identity
        )

        #expect(pages.map(\.range) == [0..<3, 3..<4])
        #expect(pages.allSatisfy {
            $0.atlas.width <= 11 && $0.atlas.height <= 11
        })

        var actualPositionX: [Float] = []
        var actualPositionY: [Float] = []
        for page in pages {
            let pagePositions = page.range.map { index in
                OpenCoreGraphics.CGPoint(
                    x: originalPositions[index].x + Double(index) * 2,
                    y: originalPositions[index].y
                )
            }
            let vertices = GLRendererGeometry.glyphVertices(
                Array(originalGlyphs[page.range]),
                positions: pagePositions,
                glyphAtlas: page.atlas,
                characterSpacing: 0,
                textMatrix: .identity,
                textPosition: .zero,
                ctm: .identity
            )
            actualPositionX.append(contentsOf: vertices.map { $0.positionX })
            actualPositionY.append(contentsOf: vertices.map { $0.positionY })
        }

        #expect(actualPositionX == expected.map { $0.positionX })
        #expect(actualPositionY == expected.map { $0.positionY })
        #expect(pages[0].atlas.glyphs[1] == nil)
        #expect(pages[0].atlas.glyphs[0]?.width == 2)
        #expect(pages[0].atlas.glyphs[2]?.width == 2)
        #expect(pages[1].atlas.glyphs[0]?.width == 2)
    }

    /// Rejects a single glyph whose padded texture footprint exceeds the simulated limit.
    @Test
    func reportsGlyphThatCannotFit() throws {
        let bitmap = CGGlyphBitmap(
            width: 2,
            height: 2,
            xOffset: 0,
            yOffset: 0,
            coverage: Data(repeating: 255, count: 4)
        )
        let atlas = try #require(CGGlyphAtlas(bitmaps: [bitmap]))

        #expect(throws: CGGlyphAtlasPaginationError.glyphExceedsTextureLimit(
            width: 4,
            height: 4,
            limit: 3
        )) {
            try atlas.pages(maxTextureSize: 3)
        }
    }

    /// Rejects a nonpositive device limit rather than returning an unbounded page.
    @Test
    func rejectsInvalidTextureLimit() throws {
        let bitmap = CGGlyphBitmap(
            width: 1,
            height: 1,
            xOffset: 0,
            yOffset: 0,
            coverage: Data([255])
        )
        let atlas = try #require(CGGlyphAtlas(bitmaps: [bitmap]))

        #expect(throws: CGGlyphAtlasPaginationError.invalidTextureLimit) {
            try atlas.pages(maxTextureSize: 0)
        }
    }
}

/// Tests that glyph texture upload failures remain typed through the cache.
@MainActor
struct GLGlyphTextureFailureTests {
    /// Propagates an upload error instead of caching an incomplete glyph texture.
    @Test
    func propagatesGlyphUploadFailure() throws {
        let bitmap = CGGlyphBitmap(
            width: 1,
            height: 1,
            xOffset: 0,
            yOffset: 0,
            coverage: Data([255])
        )
        let atlas = try #require(CGGlyphAtlas(bitmaps: [bitmap]))
        let cache = GLTextureCache(loader: FailingGlyphTextureLoader(
            failure: .uploadFailed(UInt32(0x0505))
        ))

        #expect(throws: GLTextureError.uploadFailed(UInt32(0x0505))) {
            try cache.texture(for: atlas)
        }
    }
}

/// A glyph loader that deterministically fails texture upload without calling OpenGL.
@MainActor
private struct FailingGlyphTextureLoader: GLTextureLoader {
    /// The typed error returned for every texture operation.
    let failure: GLTextureError

    /// Fails image allocation because this loader only supports failure-path tests.
    func makeTexture(from image: CGImageSnapshot) throws -> GLTexture {
        throw failure
    }

    /// Fails glyph allocation or upload without creating a GL resource.
    func makeTexture(from glyphAtlas: CGGlyphAtlas) throws -> GLTexture {
        throw failure
    }

    /// Fails image updates because this loader has no allocated texture.
    func updateTexture(_ texture: GLTexture, from image: CGImageSnapshot) throws {
        throw failure
    }
}
