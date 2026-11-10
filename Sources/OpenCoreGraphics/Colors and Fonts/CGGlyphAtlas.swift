import Foundation

/// A row-packed atlas of 8-bit glyph coverage masks.
struct CGGlyphAtlas: Equatable, Sendable {
    /// The location and text-space bearings of one glyph within the atlas.
    struct Glyph: Equatable, Sendable {
        /// The horizontal atlas coordinate of the glyph's first coverage pixel.
        let atlasX: Int

        /// The vertical atlas coordinate of the glyph's first coverage pixel.
        let atlasY: Int

        /// The glyph bitmap width in pixels.
        let width: Int

        /// The glyph bitmap height in pixels.
        let height: Int

        /// The horizontal offset from the glyph origin.
        let xOffset: Int

        /// The vertical offset from the text baseline in stb's bitmap coordinates.
        let yOffset: Int
    }

    /// The stable identity used to reuse the atlas texture.
    let identity: UUID

    /// The atlas width in pixels.
    let width: Int

    /// The atlas height in pixels.
    let height: Int

    /// The row-major, 8-bit coverage pixels.
    let coverage: Data

    /// The atlas region for each input glyph, or nil when the glyph has no bitmap.
    let glyphs: [Glyph?]

    /// Packs glyph masks horizontally with a one-pixel transparent gutter.
    /// - Parameter bitmaps: The coverage masks in glyph-index order.
    /// - Returns: A packed atlas, or nil when its dimensions or source masks are invalid.
    init?(bitmaps: [CGGlyphBitmap?]) {
        var visibleBitmaps: [(index: Int, bitmap: CGGlyphBitmap)] = []
        for (index, optionalBitmap) in bitmaps.enumerated() {
            guard let bitmap = optionalBitmap else { continue }
            guard bitmap.width >= 0, bitmap.height >= 0 else { return nil }
            let (pixelCount, pixelCountOverflow) = bitmap.width.multipliedReportingOverflow(by: bitmap.height)
            guard pixelCountOverflow == false, bitmap.coverage.count >= pixelCount else { return nil }
            if bitmap.width > 0, bitmap.height > 0 {
                visibleBitmaps.append((index, bitmap))
            }
        }
        guard visibleBitmaps.isEmpty == false else { return nil }

        var atlasWidth = 1
        var atlasHeight = 1
        for entry in visibleBitmaps {
            let (glyphWidth, glyphWidthOverflow) = entry.bitmap.width.addingReportingOverflow(2)
            let (nextWidth, widthOverflow) = atlasWidth.addingReportingOverflow(glyphWidth)
            let (glyphHeight, glyphHeightOverflow) = entry.bitmap.height.addingReportingOverflow(2)
            guard glyphWidthOverflow == false,
                  widthOverflow == false,
                  glyphHeightOverflow == false else {
                return nil
            }
            atlasWidth = nextWidth
            atlasHeight = max(atlasHeight, glyphHeight)
        }
        let (byteCount, byteCountOverflow) = atlasWidth.multipliedReportingOverflow(by: atlasHeight)
        guard byteCountOverflow == false else { return nil }

        var atlasCoverage = [UInt8](repeating: 0, count: byteCount)
        var atlasGlyphs = [Glyph?](repeating: nil, count: bitmaps.count)
        var atlasX = 1
        for entry in visibleBitmaps {
            for row in 0..<entry.bitmap.height {
                let sourceStart = row * entry.bitmap.width
                let destinationStart = (row + 1) * atlasWidth + atlasX
                let sourceRange = sourceStart..<(sourceStart + entry.bitmap.width)
                let destinationRange = destinationStart..<(destinationStart + entry.bitmap.width)
                atlasCoverage.replaceSubrange(destinationRange, with: entry.bitmap.coverage[sourceRange])
            }
            atlasGlyphs[entry.index] = Glyph(
                atlasX: atlasX,
                atlasY: 1,
                width: entry.bitmap.width,
                height: entry.bitmap.height,
                xOffset: entry.bitmap.xOffset,
                yOffset: entry.bitmap.yOffset
            )
            atlasX += entry.bitmap.width + 2
        }

        identity = UUID()
        width = atlasWidth
        height = atlasHeight
        coverage = Data(atlasCoverage)
        glyphs = atlasGlyphs
    }
}
