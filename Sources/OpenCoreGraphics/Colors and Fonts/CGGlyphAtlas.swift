import Foundation

/// A failure while splitting a glyph atlas into device-sized textures.
package enum CGGlyphAtlasPaginationError: Error, Equatable {
    /// The requested maximum texture dimension is not positive.
    case invalidTextureLimit

    /// One glyph, including its transparent gutter, cannot fit in a texture.
    case glyphExceedsTextureLimit(width: Int, height: Int, limit: Int)

    /// The captured atlas data or one of its glyph regions is invalid.
    case invalidAtlas

    /// A valid page could not be assembled from the captured glyph masks.
    case pageAllocationFailed
}

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

    /// Splits consecutive glyphs into row-packed pages that fit a device texture limit.
    /// - Parameter maxTextureSize: The maximum width and height queried from the owning GL context.
    /// - Returns: Ordered glyph-index ranges paired with their bounded atlases.
    /// - Throws: `CGGlyphAtlasPaginationError` when the limit, source atlas, or a glyph is invalid.
    package func pages(
        maxTextureSize: Int
    ) throws -> [(range: Range<Int>, atlas: CGGlyphAtlas)] {
        guard maxTextureSize > 0 else {
            throw CGGlyphAtlasPaginationError.invalidTextureLimit
        }
        let (sourceByteCount, sourceByteOverflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0,
              height > 0,
              sourceByteOverflow == false,
              coverage.count == sourceByteCount,
              glyphs.isEmpty == false else {
            throw CGGlyphAtlasPaginationError.invalidAtlas
        }

        var result: [(range: Range<Int>, atlas: CGGlyphAtlas)] = []
        var pageStart = 0
        var pageBitmaps: [CGGlyphBitmap?] = []
        var pageWidth = 1
        var containsVisibleGlyph = false

        func appendPage(endingAt endIndex: Int) throws {
            guard containsVisibleGlyph else { return }
            guard let pageAtlas = CGGlyphAtlas(bitmaps: pageBitmaps),
                  pageAtlas.width <= maxTextureSize,
                  pageAtlas.height <= maxTextureSize else {
                throw CGGlyphAtlasPaginationError.pageAllocationFailed
            }
            result.append((pageStart..<endIndex, pageAtlas))
        }

        for index in glyphs.indices {
            let bitmap: CGGlyphBitmap?
            if let glyph = glyphs[index] {
                guard glyph.width > 0,
                      glyph.height > 0,
                      glyph.atlasX >= 0,
                      glyph.atlasY >= 0,
                      glyph.atlasX <= width - glyph.width,
                      glyph.atlasY <= height - glyph.height else {
                    throw CGGlyphAtlasPaginationError.invalidAtlas
                }
                let (pixelCount, pixelOverflow) = glyph.width.multipliedReportingOverflow(by: glyph.height)
                guard pixelOverflow == false else {
                    throw CGGlyphAtlasPaginationError.invalidAtlas
                }
                var pixels = Data()
                pixels.reserveCapacity(pixelCount)
                for row in 0..<glyph.height {
                    let start = (glyph.atlasY + row) * width + glyph.atlasX
                    pixels.append(coverage.subdata(in: start..<(start + glyph.width)))
                }
                bitmap = CGGlyphBitmap(
                    width: glyph.width,
                    height: glyph.height,
                    xOffset: glyph.xOffset,
                    yOffset: glyph.yOffset,
                    coverage: pixels
                )
            } else {
                bitmap = nil
            }

            if let bitmap {
                let (requiredWidth, widthOverflow) = bitmap.width.addingReportingOverflow(2)
                let (requiredHeight, heightOverflow) = bitmap.height.addingReportingOverflow(2)
                guard widthOverflow == false,
                      heightOverflow == false,
                      requiredWidth <= maxTextureSize,
                      requiredHeight <= maxTextureSize else {
                    throw CGGlyphAtlasPaginationError.glyphExceedsTextureLimit(
                        width: widthOverflow ? Int.max : requiredWidth,
                        height: heightOverflow ? Int.max : requiredHeight,
                        limit: maxTextureSize
                    )
                }

                let (candidateWidth, candidateOverflow) = pageWidth.addingReportingOverflow(requiredWidth)
                if containsVisibleGlyph && (candidateOverflow || candidateWidth > maxTextureSize) {
                    try appendPage(endingAt: index)
                    pageStart = index
                    pageBitmaps.removeAll(keepingCapacity: true)
                    pageWidth = 1
                    containsVisibleGlyph = false
                }
                let (nextWidth, nextWidthOverflow) = pageWidth.addingReportingOverflow(requiredWidth)
                guard nextWidthOverflow == false, nextWidth <= maxTextureSize else {
                    throw CGGlyphAtlasPaginationError.pageAllocationFailed
                }
                pageWidth = nextWidth
                containsVisibleGlyph = true
            }
            pageBitmaps.append(bitmap)
        }

        try appendPage(endingAt: glyphs.count)
        return result
    }
}
