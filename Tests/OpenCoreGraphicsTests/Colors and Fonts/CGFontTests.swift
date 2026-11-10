import Foundation
import Testing
@testable import OpenCoreGraphics

/// Tests TrueType loading, character mapping, and horizontal font metrics.
struct CGFontTests {
    /// Verifies a bundled TrueType font provides glyph mappings and advances.
    @Test
    func loadsGlyphsAndMetricsFromTrueTypeFont() throws {
        let url = try #require(
            Bundle.module.url(forResource: "tiny-test", withExtension: "ttf", subdirectory: "Resources")
        )
        let font = try #require(CGFont(url.path))
        let aGlyph = try #require(font.glyph(for: "A"))
        let iGlyph = try #require(font.glyph(for: "I"))

        #expect(font.unitsPerEm == 1000)
        #expect(font.numberOfGlyphs == 3)
        #expect(font.ascent == 800)
        #expect(font.descent == -200)
        #expect(font.advance(for: aGlyph) == 700)
        #expect(font.advance(for: iGlyph) == 350)
        #expect(font.glyph(for: "B") == nil)
        #expect(font.advance(for: CGGlyph.max) == nil)
    }

    /// Verifies missing files, invalid bytes, and multi-scalar characters are rejected.
    @Test
    func rejectsMissingInvalidAndUnsupportedFontInputs() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let invalidURL = missingURL.appendingPathExtension("ttf")
        try Data(repeating: 0x41, count: 64).write(to: invalidURL)
        defer { try? FileManager.default.removeItem(at: invalidURL) }

        #expect(CGFont(missingURL.path) == nil)
        #expect(CGFont(invalidURL.path) == nil)

        let url = try #require(
            Bundle.module.url(forResource: "tiny-test", withExtension: "ttf", subdirectory: "Resources")
        )
        let font = try #require(CGFont(url.path))
        let multiScalarCharacter: Character = "e\u{301}"
        #expect(font.glyph(for: multiScalarCharacter) == nil)
    }
}
