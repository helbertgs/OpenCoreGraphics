import Foundation
import OpenCoreGraphicsSTB

/// A set of character glyphs and layout information for drawing text.
/// 
/// A glyph can represent a single character (such as ‘b’), more than one character (such as the “ﬁ” ligature), or a special character such as a space. 
/// Core Graphics retrieves the glyphs for the font from ATS (Apple Type Services) and paints the glyphs based on the relevant parameters of the current graphics state.
/// 
/// Core Graphics provides a limited, low-level interface for drawing text.
public class CGFont {

    /// The stable byte buffer referenced by the parsed TrueType font tables.
    private var fontBuffer: UnsafeMutablePointer<UInt8>?

    /// The font metadata cached by `stb_truetype`.
    private var fontInfo: OpaquePointer?

    /// The number of font units per em square.
    public private(set) var unitsPerEm = 0

    // MARK: - Creating Font Objects

    /// Creates a font object from a TrueType font file.
    ///
    /// The argument is a filesystem path, not a PostScript name or a font-family
    /// name. This initializer does not search installed fonts by name.
    ///
    /// ```swift
    /// guard let font = CGFont("/path/to/font.ttf") else {
    ///     // Handle a missing, unreadable, or unsupported font file.
    ///     return
    /// }
    /// context.setFont(font)
    /// ```
    ///
    /// Before drawing text in a graphics context, set the font in its current
    /// graphics state by calling ``CGContext/setFont(_:)``.
    /// - Parameter name: The path to a TrueType font file.
    /// - Returns: A font object, or `nil` if the file cannot be read or parsed.
    public init?(_ name: String) {
        self.fullName = name

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: name)),
              data.count >= 20,
              data.count <= Int(Int32.max) else {
            return nil
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        data.copyBytes(to: buffer, count: data.count)
        guard let parsedFontInfo = ocg_stb_font_create(buffer, Int32(data.count)) else {
            buffer.deallocate()
            return nil
        }

        fontBuffer = buffer
        fontInfo = parsedFontInfo
        unitsPerEm = Int(ocg_stb_font_units_per_em(parsedFontInfo))
        numberOfGlyphs = Int(ocg_stb_font_glyph_count(parsedFontInfo))

        var fontAscent: Int32 = 0
        var fontDescent: Int32 = 0
        var fontLineGap: Int32 = 0
        ocg_stb_font_get_vertical_metrics(
            parsedFontInfo,
            &fontAscent,
            &fontDescent,
            &fontLineGap
        )
        ascent = Int(fontAscent)
        descent = Int(fontDescent)
        leading = Int(fontLineGap)

        var minX: Int32 = 0
        var minY: Int32 = 0
        var maxX: Int32 = 0
        var maxY: Int32 = 0
        ocg_stb_font_get_bounding_box(
            parsedFontInfo,
            &minX,
            &minY,
            &maxX,
            &maxY
        )
        fontBBox = CGRect(
            x: Double(minX),
            y: Double(minY),
            width: Double(maxX - minX),
            height: Double(maxY - minY)
        )
    }

    /// Releases the stable byte buffer referenced by the parsed font.
    deinit {
        if let fontInfo {
            ocg_stb_font_destroy(fontInfo)
        }
        fontBuffer?.deallocate()
    }

    // MARK: - Examining Font Metadata

    /// Returns the full name associated with a font object.
    public var fullName: String = ""

    // MARK: - Working with Font Tables

    /// Returns an array of tags that correspond to the font tables for a font.
    public private(set) lazy var tableTags: Array<UInt8> = .init(
        repeating: 0, 
        count: width * height
    )

    /// Returns the font table that corresponds to the provided tag.
    /// - Parameter tag: The tag for the table you want to obtain.
    /// - Returns: The font table that corresponds to the tag, or nil if no such table exists.
    public func table(for tag: Int) -> Data? {
        nil
    }

    // MARK: - Examining Font Metrics

    /// The font id.
    private(set) var id: UInt32 = 0

    /// The first ASCII codepoint to bake (e.g., 32 for space).
    private var firstChar: Int = 32

    /// Width of the baked glyph atlas.
    private var width: Int = 512

    /// Height of the baked glyph atlas.
    private var height: Int = 512

    /// Returns the ascent of a font.
    /// 
    /// The ascent is the maximum distance above the baseline of glyphs in a font. 
    /// The value is specified in glyph space units.
    public var ascent: Int = 0

    /// Returns the cap height of a font.
    /// 
    /// The cap height is the distance above the baseline of the top of flat capital letters of glyphs in a font. 
    /// The value is specified in glyph space units.
    public var capHeight: Int = 0

    /// Returns the descent of a font.
    /// 
    /// The descent is the maximum distance below the baseline of glyphs in a font. 
    /// The value is specified in glyph space units.
    public var descent: Int = 0

    /// Returns the bounding box of a font.
    /// 
    /// The font bounding box is the union of all of the bounding boxes for all the glyphs in a font. 
    /// The value is specified in glyph space units.
    public var fontBBox: CGRect = .zero

    /// Returns the leading of a font.
    /// 
    /// The leading is the spacing between consecutive lines of text in a font. 
    /// The value is specified in glyph space units.
    public var leading: Int = 0

    /// Returns the x-height of a font.
    /// 
    /// The x-height is the distance above the baseline of the top of flat, non-ascending lowercase letters (such as x) of glyphs in a font. 
    /// The value is specified in glyph space units.
    public var xHeight: Int = 0

    // MARK: - Working with Glyphs

    /// Returns the number of glyphs in a font.
    public var numberOfGlyphs: Int = 96

    /// Finds the glyph associated with a single-scalar character.
    /// - Parameter character: The character whose glyph index is requested.
    /// - Returns: The glyph index, or nil when the character is unsupported by this font.
    public func glyph(for character: Character) -> CGGlyph? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              fontInfo != nil,
              scalar.value <= UInt32(Int32.max) else {
            return nil
        }
        guard let fontInfo else { return nil }
        let glyphIndex = ocg_stb_font_find_glyph_index(fontInfo, Int32(scalar.value))
        guard glyphIndex > 0, glyphIndex <= Int32(UInt16.max) else { return nil }
        return CGGlyph(glyphIndex)
    }

    /// Returns the horizontal advance of a glyph in font units.
    /// - Parameter glyph: The glyph whose advance width is requested.
    /// - Returns: The advance width, or nil when the glyph index is outside the font.
    public func advance(for glyph: CGGlyph) -> Double? {
        guard Int(glyph) < numberOfGlyphs, let fontInfo else { return nil }
        var advanceWidth: Int32 = 0
        var leftSideBearing: Int32 = 0
        ocg_stb_font_get_glyph_horizontal_metrics(
            fontInfo,
            Int32(glyph),
            &advanceWidth,
            &leftSideBearing
        )
        return Double(advanceWidth)
    }

    /// Rasterizes a glyph as an 8-bit coverage bitmap at the requested pixel height.
    /// - Parameters:
    ///   - glyph: The glyph index to rasterize.
    ///   - size: The requested font height in pixels.
    /// - Returns: The glyph bitmap, or nil when the glyph or size is invalid.
    func rasterizedGlyph(_ glyph: CGGlyph, at size: Double) -> CGGlyphBitmap? {
        guard Int(glyph) < numberOfGlyphs,
              let fontInfo,
              size.isFinite,
              size > 0,
              size <= Double(Float.greatestFiniteMagnitude) else {
            return nil
        }

        var width: Int32 = 0
        var height: Int32 = 0
        var xOffset: Int32 = 0
        var yOffset: Int32 = 0
        let bitmap = ocg_stb_font_rasterize_glyph(
            fontInfo,
            Int32(glyph),
            Float(size),
            &width,
            &height,
            &xOffset,
            &yOffset
        )

        guard width >= 0, height >= 0 else { return nil }
        let (pixelCount, overflow) = Int(width).multipliedReportingOverflow(by: Int(height))
        guard overflow == false else { return nil }

        let coverage: Data
        if let bitmap {
            defer { ocg_stb_font_free_glyph_bitmap(bitmap) }
            guard pixelCount > 0 else { return nil }
            coverage = Data(bytes: bitmap, count: pixelCount)
        } else {
            guard width == 0 || height == 0 else { return nil }
            coverage = Data()
        }

        return CGGlyphBitmap(
            width: Int(width),
            height: Int(height),
            xOffset: Int(xOffset),
            yOffset: Int(yOffset),
            coverage: coverage
        )
    }

    /// Returns the glyph name of the specified glyph in the specified font.
    /// - Parameter glyph: The glyph whose name is desired.
    /// - Returns: The name of the specified glyph, or nil if the glyph isn’t associated with the font object.
    public func name(for glyph: CGGlyph) -> String? {
        nil
    }
}