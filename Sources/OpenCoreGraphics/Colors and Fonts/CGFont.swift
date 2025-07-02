import Foundation
import OpenSTB
@preconcurrency import OpenGLAD

/// A set of character glyphs and layout information for drawing text.
/// 
/// A glyph can represent a single character (such as ‘b’), more than one character (such as the “ﬁ” ligature), or a special character such as a space. 
/// Core Graphics retrieves the glyphs for the font from ATS (Apple Type Services) and paints the glyphs based on the relevant parameters of the current graphics state.
/// 
/// Core Graphics provides a limited, low-level interface for drawing text.
public class CGFont {

    // MARK: - Creating Font Objects

    /// Creates a font object corresponding to the font specified by a PostScript or full name.
    /// 
    /// Before drawing text in a Core Graphics context, you must set the font in the current graphics state by calling the function ``setFont(_:)``.
    /// - Parameter name: The PostScript or full name of a font.
    public init?(_ name: String) {
        self.fullName = name

        guard let data = try? Data(contentsOf: .init(fileURLWithPath: name)) else {
            return nil
        }

        print("Font data: \(data)")

        // var info = stbtt_fontinfo()
        // var charData = Array<stbtt_bakedchar>.init(repeating: stbtt_bakedchar(), count: 96)

        // data.withUnsafeBytes { pointer in
        //     guard let rawPointer = pointer.bindMemory(to: UInt8.self).baseAddress else { return }

        //     // Initialize font info for metrics if needed
        //     stbtt_InitFont(&info, rawPointer, 0)

        //     // Bake glyph bitmap into CPU memory
        //     stbtt_BakeFontBitmap(rawPointer, 0, Float(32), &tableTags, Int32(width), Int32(height), Int32(firstChar), Int32(numberOfGlyphs), &charData)
        // }

        // // Creates and uploads the baked glyph atlas as an OpenGL texture
        // glad_glGenTextures(1, &id)
        // glad_glBindTexture(GLenum(GL_TEXTURE_2D), id)
        // glad_glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)

        // glad_glTexImage2D(GLenum(GL_TEXTURE_2D), 0,  GL_RED,  GLsizei(width),  GLsizei(height),  0,  GLenum(GL_RED),  GLenum(GL_UNSIGNED_BYTE), &tableTags)

        // glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLint(GL_LINEAR))
        // glad_glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLint(GL_LINEAR))

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

    /// Accessor for the baked character data
    // private(set) lazy var charData: Array<stbtt_bakedchar> = .init(
    //     repeating: stbtt_bakedchar(), 
    //     count: Int(numberOfGlyphs)
    // )

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

    /// Returns the glyph name of the specified glyph in the specified font.
    /// - Parameter glyph: The glyph whose name is desired.
    /// - Returns: The name of the specified glyph, or nil if the glyph isn’t associated with the font object.
    public func name(for glyph: CGGlyph) -> String? {
        nil
    }
}