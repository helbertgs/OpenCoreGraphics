import Foundation
import Testing
@testable import OpenCoreGraphics

/// Verifies the software renderer's baseline and orientation using an asymmetric glyph mask.
struct SoftwareGlyphOrientationTests {
    /// Verifies the synthetic bitmap and its transparent atlas gutters retain stb row order.
    @Test
    private func packsAsymmetricBitmapWithoutReorderingRows() throws {
        let bitmap = makeBitmap(yOffset: -3)
        let atlas = try #require(CGGlyphAtlas(bitmaps: [bitmap]))
        let glyph = try #require(atlas.glyphs.first ?? nil)

        #expect(bitmap.width == 2)
        #expect(bitmap.height == 3)
        #expect(bitmap.xOffset == 1)
        #expect(bitmap.yOffset == -3)
        #expect(Array(bitmap.coverage) == [255, 32, 64, 192, 128, 0])
        #expect(atlas.width == 5)
        #expect(atlas.height == 5)
        #expect(glyph.atlasX == 1)
        #expect(glyph.atlasY == 1)
        #expect(glyph.width == 2)
        #expect(glyph.height == 3)
        #expect(glyph.xOffset == 1)
        #expect(glyph.yOffset == -3)
        #expect(Array(atlas.coverage) == [
            0, 0, 0, 0, 0,
            0, 255, 32, 0, 0,
            0, 64, 192, 0, 0,
            0, 128, 0, 0, 0,
            0, 0, 0, 0, 0
        ])
    }

    /// Verifies exact alpha above and below the baseline, including untouched neighboring pixels.
    @Test(arguments: [-3, 0])
    private func rendersRowsOnTheCorrectSideOfBaseline(yOffset: Int) throws {
        let surface = try render(yOffset: yOffset, positions: [CGPoint(x: 10, y: 10)])
        let bottom = yOffset == -3 ? 10 : 7
        expectAlpha(surface, rows: [
            [128, 0],
            [64, 192],
            [255, 32]
        ], x: 11, y: bottom)
    }

    /// Verifies a quarter turn preserves each source sample rather than just the quad bounds.
    @Test
    private func rotatesAsymmetricRows() throws {
        let surface = try render(
            positions: [CGPoint(x: 10, y: 10)],
            textMatrix: OpenCoreGraphics.CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 20, ty: 0)
        )
        expectAlpha(surface, rows: [
            [255, 64, 128],
            [32, 192, 0]
        ], x: 7, y: 11)
    }

    /// Verifies both negative CTM scales reflect the asymmetric samples in device space.
    @Test
    private func reflectsHorizontallyAndVertically() throws {
        let horizontal = try render(
            positions: [CGPoint(x: 10, y: 10)],
            ctm: OpenCoreGraphics.CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 20, ty: 0)
        )
        expectAlpha(horizontal, rows: [
            [0, 128],
            [192, 64],
            [32, 255]
        ], x: 7, y: 10)

        let vertical = try render(
            positions: [CGPoint(x: 10, y: 10)],
            ctm: OpenCoreGraphics.CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 20)
        )
        expectAlpha(vertical, rows: [
            [255, 32],
            [64, 192],
            [128, 0]
        ], x: 11, y: 7)
    }

    /// Verifies the text matrix precedes user-space text position and the scaled, translated CTM.
    @Test
    private func appliesTextPositionAndCTMInDocumentedOrder() throws {
        let textMatrix = OpenCoreGraphics.CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        let textPosition = OpenCoreGraphics.CGPoint(x: 10, y: 20)
        let ctm = OpenCoreGraphics.CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 5, ty: 7)
        let corners = [
            OpenCoreGraphics.CGPoint(x: 3, y: 3), OpenCoreGraphics.CGPoint(x: 5, y: 3),
            OpenCoreGraphics.CGPoint(x: 5, y: 6), OpenCoreGraphics.CGPoint(x: 3, y: 6)
        ].map { point in
            let transformed = point.applying(textMatrix)
            return OpenCoreGraphics.CGPoint(
                x: transformed.x + textPosition.x, y: transformed.y + textPosition.y
            ).applying(ctm)
        }
        #expect(corners == [
            CGPoint(x: 19, y: 53), CGPoint(x: 19, y: 57),
            CGPoint(x: 13, y: 57), CGPoint(x: 13, y: 53)
        ])

        let surface = try render(
            positions: [CGPoint(x: 2, y: 3)],
            textMatrix: textMatrix,
            textPosition: textPosition,
            ctm: ctm
        )
        expectAlpha(surface, rows: [
            [143, 155, 84, 60, 84, 72],
            [149, 173, 122, 96, 96, 72],
            [66, 106, 142, 128, 64, 24],
            [18, 54, 114, 108, 36, 0]
        ], x: 13, y: 53)
    }

    /// Verifies character spacing is applied in text space before horizontal scaling.
    @Test
    private func scalesCharacterSpacingWithTextMatrix() throws {
        let surface = try render(
            positions: [CGPoint(x: 2, y: 3), CGPoint(x: 8, y: 3)],
            characterSpacing: 3,
            textMatrix: OpenCoreGraphics.CGAffineTransform(a: 2, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        )
        let rows: [[UInt8]] = [
            [96, 96, 32, 0],
            [48, 96, 160, 144],
            [191, 199, 88, 24]
        ]
        expectAlpha(surface, regions: [(6, 3, rows), (24, 3, rows)])
    }

    /// Verifies clipping still restricts the oriented glyph coverage.
    @Test
    private func clipsAsymmetricGlyph() throws {
        let surface = try render(
            positions: [CGPoint(x: 10, y: 10)],
            clip: CGRect(x: 11, y: 11, width: 1, height: 2)
        )
        expectAlpha(surface, rows: [[64], [255]], x: 11, y: 11)
    }

    /// Verifies partial clip coverage multiplies glyph alpha rather than saturating it.
    @Test
    private func combinesPartialClipAndGlyphCoverage() throws {
        let surface = try render(
            positions: [CGPoint(x: 10, y: 10)],
            clip: CGRect(x: 11.5, y: 10, width: 1, height: 3)
        )
        expectAlpha(surface, rows: [[64, 0], [32, 96], [128, 16]], x: 11, y: 10)
    }

    /// Creates the documented top-down 2×3 coverage mask with the requested vertical bearing.
    private func makeBitmap(yOffset: Int) -> CGGlyphBitmap {
        CGGlyphBitmap(
            width: 2, height: 3, xOffset: 1, yOffset: yOffset,
            coverage: Data([255, 32, 64, 192, 128, 0])
        )
    }

    /// Renders synthetic glyphs into a fresh transparent software surface.
    private func render(
        yOffset: Int = -3,
        positions: [OpenCoreGraphics.CGPoint],
        characterSpacing: Double = 0,
        textMatrix: OpenCoreGraphics.CGAffineTransform = .identity,
        textPosition: OpenCoreGraphics.CGPoint = .zero,
        ctm: OpenCoreGraphics.CGAffineTransform = .identity,
        clip: OpenCoreGraphics.CGRect? = nil
    ) throws -> PixelSurface {
        let width = 64
        let height = 64
        let surface = try #require(PixelSurface(
            data: nil, width: width, height: height, bytesPerRow: width * 4,
            colorSpace: .genericRGBLinear, alphaInfo: .premultipliedLast, bitmapInfo: .byteOrderDefault
        ))
        let atlas = try #require(CGGlyphAtlas(bitmaps: positions.map { _ in makeBitmap(yOffset: yOffset) }))
        let renderer = SoftwareRenderer(surface: surface)
        if let clip {
            var path = CGPath()
            path.addRect(clip)
            let mask = try #require(CoverageMask(path: path, rule: .winding, width: width, height: height))
            renderer.setClipMask(mask)
        }
        let command = DrawCommand.glyphs(
            glyphs: positions.map { _ in 1 },
            positions: positions,
            fontName: nil,
            fontSize: 1,
            glyphAtlas: atlas,
            characterSpacing: characterSpacing,
            textMatrix: textMatrix,
            textPosition: textPosition,
            ctm: ctm,
            color: .white,
            blendMode: .normal
        )
        renderer.execute([command], size: CGSize(width: width, height: height))
        return surface
    }

    /// Compares every surface alpha against one expected rectangle and transparent surroundings.
    private func expectAlpha(_ surface: PixelSurface, rows: [[UInt8]], x: Int, y: Int) {
        expectAlpha(surface, regions: [(x, y, rows)])
    }

    /// Compares every surface alpha against expected rectangles and transparent surroundings.
    private func expectAlpha(_ surface: PixelSurface, regions: [(Int, Int, [[UInt8]])]) {
        var expected = [UInt8](repeating: 0, count: surface.width * surface.height)
        for (originX, originY, rows) in regions {
            for (rowIndex, row) in rows.enumerated() {
                for (columnIndex, alpha) in row.enumerated() {
                    expected[(originY + rowIndex) * surface.width + originX + columnIndex] = alpha
                }
            }
        }
        for y in 0..<surface.height {
            for x in 0..<surface.width {
                let alpha = surface.pixel(x: x, y: y)?.alpha
                #expect(alpha == expected[y * surface.width + x], "Pixel (\(x), \(y))")
            }
        }
    }
}
