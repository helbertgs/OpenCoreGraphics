import Foundation
import Testing
@testable import OpenCoreGraphics

/// Compares OpenGL and software glyph rendering when explicitly enabled on a display-enabled machine.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_GL_COMPARISON"] == "1"))
@MainActor
struct GLGlyphComparisonTests {
    /// Verifies the OpenGL glyph shader matches the software renderer for the bundled font fixture.
    @Test
    func comparesGlyphRenderingAcrossBackends() throws {
        let window: CGWindow
        do {
            window = try CGWindow(frame: CGRect(x: 0, y: 0, width: 64, height: 64), title: "Glyph comparison")
        } catch let error as CGWindowError {
            print("GL_RUNNER_GRAPHICS_UNAVAILABLE: \(error)")
            throw error
        }
        let glContext = window.cgContext
        let softwareContext = try #require(
            CGContext(
                data: nil,
                width: glContext.width,
                height: glContext.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: .sRGB,
                bitmapInfo: 0
            )
        )
        let font = try sampleFont()

        drawGlyphs(in: glContext, font: font)
        drawGlyphs(in: softwareContext, font: font)
        glContext.flush()
        softwareContext.flush()

        let glPixels = try #require(glContext.renderTarget?.readPixels())
        let normalizedGLPixels = try GLComparisonPixels(pixels: glPixels).data
        let softwarePixels = try GLComparisonPixels(pixels: softwareContext.data, storedAsSRGB: true).data
        let difference = try #require(meanChannelDifference(normalizedGLPixels, softwarePixels))
        _ = try GLComparisonReport(
            scene: "glyphs",
            width: glContext.width,
            height: glContext.height,
            difference: difference,
            tolerance: 4.0 / 255.0,
            glPixels: glPixels,
            softwarePixels: softwarePixels
        )
        #expect(difference <= 4.0 / 255.0, "Glyph rendering mean channel difference was \(difference)")
    }

    /// Loads the bundled font fixture for deterministic glyph rendering.
    /// - Returns: The parsed TrueType font.
    private func sampleFont() throws -> CGFont {
        let fontURL = try #require(
            Bundle.module.url(forResource: "tiny-test", withExtension: "ttf", subdirectory: "Resources")
        )
        return try #require(CGFont(fontURL.path))
    }

    /// Draws two fixture glyphs at a baseline with their measured horizontal advances.
    /// - Parameters:
    ///   - context: The destination graphics context.
    ///   - font: The fixture font containing the glyphs.
    private func drawGlyphs(in context: CGContext, font: CGFont) {
        guard font.unitsPerEm > 0 else {
            preconditionFailure("The glyph fixture must have valid units-per-em metrics.")
        }
        context.setBlendMode(.normal)
        context.setFillColor(.black)
        context.fill(CGRect(x: 0, y: 0, width: Double(context.width), height: Double(context.height)))

        let glyphs = "IA".map { character -> CGGlyph in
            guard let glyph = font.glyph(for: character) else {
                preconditionFailure("The glyph fixture must contain \(character).")
            }
            return glyph
        }
        let fontSize = 20.0
        var positions: [OpenCoreGraphics.CGPoint] = []
        var penX = 0.0
        for glyph in glyphs {
            positions.append(CGPoint(x: penX, y: 0))
            guard let advance = font.advance(for: glyph) else {
                preconditionFailure("The glyph fixture must provide an advance for each glyph.")
            }
            penX += advance * fontSize / Double(font.unitsPerEm)
        }

        context.setFont(font)
        context.setFontSize(fontSize)
        context.setCharacterSpacing(0)
        context.textPosition = CGPoint(x: 12, y: 24)
        context.setFillColor(.white)
        context.showGlyphs(glyphs, at: positions)
    }

    /// Computes the normalized mean absolute difference across RGBA channels.
    /// - Parameters:
    ///   - first: The OpenGL RGBA pixels.
    ///   - second: The software RGBA pixels.
    /// - Returns: A value from zero to one, or nil when the buffers differ in size.
    private func meanChannelDifference(_ first: Data, _ second: Data) -> Double? {
        guard first.count == second.count, first.isEmpty == false else { return nil }
        let totalDifference = zip(first, second).reduce(0) { total, pair in
            total + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(totalDifference) / Double(first.count * 255)
    }
}
