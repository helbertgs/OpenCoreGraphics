#include <stdint.h>

typedef struct OCGSTBFont OCGSTBFont;

/// Creates a TrueType font parser that references the provided font bytes.
/// - Parameters:
///   - fontData: The font bytes, which must remain valid while the parser exists.
///   - fontDataLength: The number of bytes in the font data.
/// - Returns: An initialized parser, or `NULL` when the font data is invalid.
OCGSTBFont *ocg_stb_font_create(const unsigned char *fontData, int fontDataLength);

/// Releases a parser created by `ocg_stb_font_create`.
/// - Parameter font: The parser to release.
void ocg_stb_font_destroy(OCGSTBFont *font);

/// Returns the number of font units per em square.
/// - Parameter font: The initialized parser.
/// - Returns: The units per em value.
int ocg_stb_font_units_per_em(const OCGSTBFont *font);

/// Returns the number of glyphs in the font.
/// - Parameter font: The initialized parser.
/// - Returns: The glyph count.
int ocg_stb_font_glyph_count(const OCGSTBFont *font);

/// Reads the font's vertical metrics.
/// - Parameters:
///   - font: The initialized parser.
///   - ascent: Receives the ascent in font units.
///   - descent: Receives the descent in font units.
///   - lineGap: Receives the line gap in font units.
void ocg_stb_font_get_vertical_metrics(
    const OCGSTBFont *font,
    int *ascent,
    int *descent,
    int *lineGap
);

/// Reads the font's bounding box in font units.
/// - Parameters:
///   - font: The initialized parser.
///   - minX: Receives the minimum horizontal coordinate.
///   - minY: Receives the minimum vertical coordinate.
///   - maxX: Receives the maximum horizontal coordinate.
///   - maxY: Receives the maximum vertical coordinate.
void ocg_stb_font_get_bounding_box(
    const OCGSTBFont *font,
    int *minX,
    int *minY,
    int *maxX,
    int *maxY
);

/// Finds the glyph index for a Unicode scalar value.
/// - Parameters:
///   - font: The initialized parser.
///   - codepoint: The Unicode scalar value to look up.
/// - Returns: The glyph index, or zero when no glyph is mapped.
int ocg_stb_font_find_glyph_index(const OCGSTBFont *font, int32_t codepoint);

/// Reads the horizontal metrics for a glyph.
/// - Parameters:
///   - font: The initialized parser.
///   - glyphIndex: The glyph index to query.
///   - advanceWidth: Receives the advance width in font units.
///   - leftSideBearing: Receives the left side bearing in font units.
void ocg_stb_font_get_glyph_horizontal_metrics(
    const OCGSTBFont *font,
    int glyphIndex,
    int *advanceWidth,
    int *leftSideBearing
);
