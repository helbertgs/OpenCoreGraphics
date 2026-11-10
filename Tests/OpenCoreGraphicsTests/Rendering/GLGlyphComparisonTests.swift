import Foundation
import Testing
@preconcurrency import OpenGLAD
import OpenGLFW
@testable import OpenCoreGraphics

/// Calculates both whole-frame mean and worst-channel errors against an independent reference.
private func glyphComparisonMetrics(
    gl: [UInt8], software: [UInt8], reference: [UInt8]
) -> (mean: Double, backendMaximum: Int, referenceMaximum: Int, glReferenceMaximum: Int)? {
    guard gl.isEmpty == false, gl.count.isMultiple(of: 4),
          gl.count == software.count, software.count == reference.count else { return nil }
    let differences = zip(gl, software).map { abs(Int($0) - Int($1)) }
    let referenceDifferences = zip(software, reference).map { abs(Int($0) - Int($1)) }
    return (
        Double(differences.reduce(0, +)) / (Double(gl.count) * 255),
        differences.max() ?? 255,
        referenceDifferences.max() ?? 255,
        zip(gl, reference).map { abs(Int($0) - Int($1)) }.max() ?? 255
    )
}

/// Tests that localized glyph failures cannot hide behind an acceptable global mean.
struct GlyphMetricTests {
    /// Detects a single inverted sample despite a low whole-frame mean.
    @Test
    private func localFailureCannotHideInMean() throws {
        let reference = [UInt8](repeating: 0, count: 64 * 64 * 4)
        var gl = reference
        gl[4 * (10 * 64 + 11)] = 255
        let metrics = try #require(glyphComparisonMetrics(gl: gl, software: reference, reference: reference))
        #expect(metrics.mean < 4.0 / 255)
        #expect(metrics.backendMaximum == 255)
        #expect(metrics.referenceMaximum == 0)
        #expect(metrics.glReferenceMaximum == 255)
    }

    /// Detects matching but incorrect backends against the independent expected pixels.
    @Test
    private func identicalWrongBackendsFailReference() throws {
        let wrong = [UInt8](repeating: 0, count: 16)
        var reference = wrong
        reference[0] = 128
        let metrics = try #require(glyphComparisonMetrics(gl: wrong, software: wrong, reference: reference))
        #expect(metrics.mean == 0)
        #expect(metrics.backendMaximum == 0)
        #expect(metrics.referenceMaximum == 128)
        #expect(metrics.glReferenceMaximum == 128)
    }

    /// Rejects empty, non-RGBA, and mismatched input rather than reporting a false success.
    @Test
    private func invalidBuffersAreRejected() {
        #expect(glyphComparisonMetrics(gl: [], software: [], reference: []) == nil)
        #expect(glyphComparisonMetrics(gl: [0], software: [0], reference: [0]) == nil)
        #expect(glyphComparisonMetrics(gl: [0, 0, 0, 0], software: [], reference: []) == nil)
    }
}

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
        try compareAsymmetricGlyphs(window: window, softwareContext: softwareContext)
    }

    /// Compares the documented asymmetric samples on both sides of the baseline and after transforms.
    private func compareAsymmetricGlyphs(window: CGWindow, softwareContext: CGContext) throws {
        let context = window.cgContext
        try #require(context.width >= 28 && context.height >= 57, "Framebuffer is too small for glyph fixtures")
        try #require(glfwGetCurrentContext() == window.windowRef)
        let target = try #require(context.renderTarget)
        let softwareTarget = try #require(softwareContext.renderTarget)
        let wasMultisampleEnabled = glad_glIsEnabled(GLenum(GL_MULTISAMPLE)) == GL_TRUE
        glad_glDisable(GLenum(GL_MULTISAMPLE))
        defer {
            if wasMultisampleEnabled { glad_glEnable(GLenum(GL_MULTISAMPLE)) }
        }
        let scenes: [(String, Int, [OpenCoreGraphics.CGPoint], Double,
                      OpenCoreGraphics.CGAffineTransform, OpenCoreGraphics.CGPoint,
                      OpenCoreGraphics.CGAffineTransform, [(Int, Int, [[UInt8]])])] = [
            ("above", -3, [CGPoint(x: 10, y: 10)], 0, .identity, .zero, .identity,
             [(11, 10, [[128, 0], [64, 192], [255, 32]])]),
            ("below", 0, [CGPoint(x: 10, y: 10)], 0, .identity, .zero, .identity,
             [(11, 7, [[128, 0], [64, 192], [255, 32]])]),
            ("rotation", -3, [CGPoint(x: 10, y: 10)], 0,
             CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 20, ty: 0), .zero, .identity,
             [(7, 11, [[255, 64, 128], [32, 192, 0]])]),
            ("horizontal", -3, [CGPoint(x: 10, y: 10)], 0, .identity, .zero,
             CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 20, ty: 0),
             [(7, 10, [[0, 128], [192, 64], [32, 255]])]),
            ("vertical", -3, [CGPoint(x: 10, y: 10)], 0, .identity, .zero,
             CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 20),
             [(11, 7, [[255, 32], [64, 192], [128, 0]])]),
            ("order", -3, [CGPoint(x: 2, y: 3)], 0,
             CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0), CGPoint(x: 10, y: 20),
             CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 5, ty: 7),
             [(13, 53, [[143, 155, 84, 60, 84, 72], [149, 173, 122, 96, 96, 72],
                         [66, 106, 142, 128, 64, 24], [18, 54, 114, 108, 36, 0]])]),
            ("spacing", -3, [CGPoint(x: 2, y: 3), CGPoint(x: 8, y: 3)], 3,
             CGAffineTransform(a: 2, b: 0, c: 0, d: 1, tx: 0, ty: 0), .zero, .identity,
             [(6, 3, [[96, 96, 32, 0], [48, 96, 160, 144], [191, 199, 88, 24]]),
              (24, 3, [[96, 96, 32, 0], [48, 96, 160, 144], [191, 199, 88, 24]])])
        ]
        for (name, yOffset, positions, spacing, matrix, textPosition, ctm, regions) in scenes {
            try #require(glfwGetCurrentContext() == window.windowRef)
            for destination in [context, softwareContext] {
                destination.setFillColor(.black)
                destination.fill(CGRect(x: 0, y: 0, width: Double(context.width), height: Double(context.height)))
                destination.flush()
            }
            let bitmap = CGGlyphBitmap(
                width: 2, height: 3, xOffset: 1, yOffset: yOffset,
                coverage: Data([255, 32, 64, 192, 128, 0])
            )
            let atlas = try #require(CGGlyphAtlas(bitmaps: positions.map { _ in bitmap }))
            let command = DrawCommand.glyphs(
                glyphs: positions.map { _ in 1 }, positions: positions, fontName: nil, fontSize: 1,
                glyphAtlas: atlas, characterSpacing: spacing, textMatrix: matrix, textPosition: textPosition,
                ctm: ctm, color: .white, blendMode: .normal
            )
            target.submit(command)
            softwareTarget.submit(command)
            target.flush()
            softwareTarget.flush()
            let glPixels = try #require(target.readPixels())
            let softwarePixels = softwareContext.data
            let gl = [UInt8](try GLComparisonPixels(pixels: glPixels).data)
            let software = [UInt8](try GLComparisonPixels(pixels: softwarePixels, storedAsSRGB: true).data)
            var expected = [UInt8](repeating: 0, count: context.width * context.height * 4)
            for index in stride(from: 3, to: expected.count, by: 4) { expected[index] = 255 }
            for (x, y, rows) in regions {
                for (row, values) in rows.enumerated() {
                    for (column, value) in values.enumerated() {
                        let index = ((y + row) * context.width + x + column) * 4
                        expected[index] = value
                        expected[index + 1] = value
                        expected[index + 2] = value
                    }
                }
            }
            let reference = [UInt8](try GLComparisonPixels(pixels: Data(expected), storedAsSRGB: false).data)
            let metrics = try #require(glyphComparisonMetrics(gl: gl, software: software, reference: reference))
            let difference = metrics.mean
            let maximum = metrics.backendMaximum
            let referenceMaximum = metrics.referenceMaximum
            let glReferenceMaximum = metrics.glReferenceMaximum
            let tolerance = 4.0 / 255
            _ = try GLComparisonReport(
                scene: "glyph_\(name)_mean", width: context.width, height: context.height,
                difference: difference, tolerance: tolerance, glPixels: glPixels, softwarePixels: softwarePixels
            )
            _ = try GLComparisonReport(
                scene: "glyph_\(name)_local", width: context.width, height: context.height,
                difference: Double(max(maximum, referenceMaximum, glReferenceMaximum)) / 255, tolerance: tolerance,
                glPixels: glPixels, softwarePixels: softwarePixels
            )
            #expect(difference <= tolerance, "\(name): mean \(difference)")
            #expect(maximum <= 4, "\(name): maximum GL/software channel difference \(maximum)")
            #expect(referenceMaximum <= 4, "\(name): maximum software/reference channel difference \(referenceMaximum)")
            #expect(glReferenceMaximum <= 4, "\(name): maximum GL/reference channel difference \(glReferenceMaximum)")
        }
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
