#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#define STB_TRUETYPE_IMPLEMENTATION
#include "Private/stb_truetype.h"
#pragma clang diagnostic pop

#include "include/OpenCoreGraphicsSTB.h"

#include <stdlib.h>

struct OCGSTBFont {
    stbtt_fontinfo fontInfo;
    int unitsPerEm;
};

OCGSTBFont *ocg_stb_font_create(const unsigned char *fontData, int fontDataLength) {
    if (fontData == NULL || fontDataLength < 20) {
        return NULL;
    }

    int fontOffset = stbtt_GetFontOffsetForIndex(fontData, 0);
    if (fontOffset < 0 || fontOffset > fontDataLength - 20) {
        return NULL;
    }

    stbtt_fontinfo fontInfo;
    if (stbtt_InitFont(&fontInfo, fontData, fontOffset) == 0 ||
        fontInfo.numGlyphs <= 0 ||
        fontInfo.head > (unsigned int)(fontDataLength - 20)) {
        return NULL;
    }

    int headOffset = (int)fontInfo.head;
    int unitsPerEm = ((int)fontData[headOffset + 18] << 8) | (int)fontData[headOffset + 19];
    if (unitsPerEm <= 0) {
        return NULL;
    }

    OCGSTBFont *font = malloc(sizeof(OCGSTBFont));
    if (font == NULL) {
        return NULL;
    }

    font->fontInfo = fontInfo;
    font->unitsPerEm = unitsPerEm;
    return font;
}

void ocg_stb_font_destroy(OCGSTBFont *font) {
    free(font);
}

int ocg_stb_font_units_per_em(const OCGSTBFont *font) {
    return font->unitsPerEm;
}

int ocg_stb_font_glyph_count(const OCGSTBFont *font) {
    return font->fontInfo.numGlyphs;
}

void ocg_stb_font_get_vertical_metrics(
    const OCGSTBFont *font,
    int *ascent,
    int *descent,
    int *lineGap
) {
    stbtt_GetFontVMetrics(&font->fontInfo, ascent, descent, lineGap);
}

void ocg_stb_font_get_bounding_box(
    const OCGSTBFont *font,
    int *minX,
    int *minY,
    int *maxX,
    int *maxY
) {
    stbtt_GetFontBoundingBox(&font->fontInfo, minX, minY, maxX, maxY);
}

int ocg_stb_font_find_glyph_index(const OCGSTBFont *font, int32_t codepoint) {
    return stbtt_FindGlyphIndex(&font->fontInfo, codepoint);
}

void ocg_stb_font_get_glyph_horizontal_metrics(
    const OCGSTBFont *font,
    int glyphIndex,
    int *advanceWidth,
    int *leftSideBearing
) {
    stbtt_GetGlyphHMetrics(&font->fontInfo, glyphIndex, advanceWidth, leftSideBearing);
}
