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
        try comparePagedGlyphRun(window: window, softwareContext: softwareContext, font: font)
        try rendererStopsAtFirstGlyphFailure(window: window)
        try measureCurrentPipelineFrameTimes(font: font)
    }

    /// Stops at the first glyph failure, retains it, and still flushes geometry queued before it.
    private func rendererStopsAtFirstGlyphFailure(window: CGWindow) throws {
        try #require(glfwGetCurrentContext() == window.windowRef)
        var maximumTextureSize: GLint = 0
        glad_glGetIntegerv(GLenum(GL_MAX_TEXTURE_SIZE), &maximumTextureSize)
        try #require(maximumTextureSize > 0)

        let renderer = try GLRenderer()
        let width = window.cgContext.width
        let height = window.cgContext.height
        let redBeforeFailure = DrawCommand.fillPath(
            path: CGPath(rect: CGRect(x: 4, y: 0, width: 20, height: Double(height))),
            rule: .winding,
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            blendMode: .normal
        )
        let blueAfterFailure = DrawCommand.fillPath(
            path: CGPath(rect: CGRect(x: Double(width - 24), y: 0, width: 20, height: Double(height))),
            rule: .winding,
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            blendMode: .normal
        )
        let oversizedBitmap = CGGlyphBitmap(
            width: Int(maximumTextureSize),
            height: 1,
            xOffset: 0,
            yOffset: 0,
            coverage: Data(repeating: 255, count: Int(maximumTextureSize))
        )
        let oversizedAtlas = try #require(CGGlyphAtlas(bitmaps: [oversizedBitmap]))
        let oversizedGlyphCommand = DrawCommand.glyphs(
            glyphs: [1],
            positions: [OpenCoreGraphics.CGPoint(x: 2, y: 8)],
            fontName: nil,
            fontSize: 1,
            glyphAtlas: oversizedAtlas,
            characterSpacing: 0,
            textMatrix: .identity,
            textPosition: .zero,
            ctm: .identity,
            color: .white,
            blendMode: .normal
        )
        let validAtlas = try #require(
            CGGlyphAtlas(bitmaps: [
                CGGlyphBitmap(width: 1, height: 1, xOffset: 0, yOffset: 0, coverage: Data([255]))
            ])
        )
        let secondGlyphFailureCommand = DrawCommand.glyphs(
            glyphs: [1],
            positions: [OpenCoreGraphics.CGPoint(x: 2, y: 8)],
            fontName: nil,
            fontSize: 1,
            glyphAtlas: validAtlas,
            characterSpacing: 0,
            textMatrix: .identity,
            textPosition: .zero,
            ctm: .identity,
            color: .white,
            blendMode: .normal
        )

        glad_glClearColor(0, 0, 0, 1)
        glad_glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        while glad_glGetError() != GLenum(GL_NO_ERROR) { }
        glad_glEnable(GLenum(UInt32.max))
        defer {
            while glad_glGetError() != GLenum(GL_NO_ERROR) { }
        }

        renderer.execute(
            [
                redBeforeFailure,
                oversizedGlyphCommand,
                blueAfterFailure,
                secondGlyphFailureCommand
            ],
            size: CGSize(width: width, height: height)
        )
        glad_glFinish()

        let expectedFirstFailure = GLRendererError.glyphAtlas(
            .glyphExceedsTextureLimit(
                width: Int(maximumTextureSize) + 2,
                height: 3,
                limit: Int(maximumTextureSize)
            )
        )
        #expect(renderer.renderingError == expectedFirstFailure)

        let pixels = try #require(renderer.readPixels(size: CGSize(width: width, height: height)))
        let row = height / 2
        let redOffset = (row * width + 8) * 4
        let blueOffset = (row * width + width - 14) * 4
        #expect(pixels[redOffset] > 200)
        #expect(pixels[redOffset + 1] < 20)
        #expect(pixels[redOffset + 2] < 20)
        #expect(pixels[blueOffset] < 20)
        #expect(pixels[blueOffset + 1] < 20)
        #expect(pixels[blueOffset + 2] < 20)

        renderer.execute([blueAfterFailure], size: CGSize(width: width, height: height))
        #expect(renderer.renderingError == expectedFirstFailure)
    }

    /// Forces the production GL renderer to split a long run at its queried texture limit.
    /// - Parameters:
    ///   - window: The window owning the GL context and its framebuffer.
    ///   - softwareContext: The independent bitmap renderer used for pixel comparison.
    ///   - font: The bundled font used to rasterize the repeated glyph.
    private func comparePagedGlyphRun(
        window: CGWindow,
        softwareContext: CGContext,
        font: CGFont
    ) throws {
        let context = window.cgContext
        let target = try #require(context.renderTarget as? WindowRenderTarget)
        _ = target.readPixels()
        try #require(glfwGetCurrentContext() == window.windowRef)
        var maximumTextureSize: GLint = 0
        glad_glGetIntegerv(GLenum(GL_MAX_TEXTURE_SIZE), &maximumTextureSize)
        try #require(maximumTextureSize > 0)

        while glad_glGetError() != GLenum(GL_NO_ERROR) { }
        glad_glEnable(GLenum(UInt32.max))
        let errorProbeBitmap = CGGlyphBitmap(
            width: 1,
            height: 1,
            xOffset: 0,
            yOffset: 0,
            coverage: Data([255])
        )
        let errorProbeAtlas = try #require(CGGlyphAtlas(bitmaps: [errorProbeBitmap]))
        #expect(throws: GLTextureError.preexistingGraphicsError(UInt32(GL_INVALID_ENUM))) {
            try OpenGLTextureLoader().makeTexture(from: errorProbeAtlas)
        }
        #expect(glad_glGetError() == GLenum(GL_NO_ERROR))

        let glyph = try #require(font.glyph(for: "I"))
        let fontSize = 24.0
        let bitmap = font.rasterizedGlyph(glyph, at: fontSize)
        let bitmapWidth = try #require(bitmap?.width)
        let bitmapHeight = try #require(bitmap?.height)
        let framebufferWidth = context.width
        let framebufferHeight = context.height
        let pageBoundary = framebufferWidth / 2
        try #require(
            pageBoundary > bitmapWidth + 4,
            "Framebuffer is too narrow to show a glyph on each side of the page boundary"
        )
        try #require(
            framebufferHeight > bitmapHeight + 4,
            "Framebuffer is too short to show the glyph"
        )
        let glyphFootprint = bitmapWidth + 2
        let glyphCount = Int(maximumTextureSize) / glyphFootprint + 1
        let bitmaps = [CGGlyphBitmap?](repeating: bitmap, count: glyphCount)
        let atlas = try #require(CGGlyphAtlas(bitmaps: bitmaps))
        let pages = try atlas.pages(maxTextureSize: Int(maximumTextureSize))
        #expect(pages.count > 1)
        #expect(pages.allSatisfy {
            $0.atlas.width <= Int(maximumTextureSize)
                && $0.atlas.height <= Int(maximumTextureSize)
        })

        let glyphs = [CGGlyph](repeating: glyph, count: glyphCount)
        let nextPageStart = pages[0].range.upperBound
        let beforeBoundaryX = Double(pageBoundary - bitmapWidth - 2)
        let afterBoundaryX = Double(pageBoundary + 2)
        let glyphBaselineY = Double(framebufferHeight / 2)
        var positions: [OpenCoreGraphics.CGPoint] = []
        positions.reserveCapacity(glyphCount)
        for index in 0..<glyphCount {
            let x: Double
            if index == 0 {
                x = beforeBoundaryX
            } else if index == nextPageStart {
                x = afterBoundaryX
            } else if index == nextPageStart - 1 {
                x = beforeBoundaryX
            } else {
                x = Double(context.width + index * Int(fontSize))
            }
            positions.append(OpenCoreGraphics.CGPoint(
                x: x,
                y: glyphBaselineY
            ))
        }
        for destination in [context, softwareContext] {
            destination.setFillColor(.black)
            destination.fill(CGRect(x: 0, y: 0, width: Double(context.width), height: Double(context.height)))
            destination.setFillColor(.white)
            destination.setFont(font)
            destination.setFontSize(fontSize)
            destination.setCharacterSpacing(0)
            destination.textPosition = .zero
            destination.showGlyphs(glyphs, at: positions)
        }
        context.flush()
        softwareContext.flush()
        try #require(target.renderingError == nil, "The GL renderer reported a glyph-page failure")

        let glPixels = try #require(target.readPixels())
        let normalizedGLPixels = try GLComparisonPixels(pixels: glPixels).data
        let normalizedSoftwarePixels = try GLComparisonPixels(
            pixels: softwareContext.data,
            storedAsSRGB: true
        ).data
        let difference = try #require(meanChannelDifference(normalizedGLPixels, normalizedSoftwarePixels))
        try #require(framebufferWidth >= 4, "Framebuffer is too narrow for split-page regions")
        let beforeRegion = try glyphPagingRegionMetrics(
            glPixels: normalizedGLPixels,
            softwarePixels: normalizedSoftwarePixels,
            width: framebufferWidth,
            height: framebufferHeight,
            xRange: 0..<pageBoundary
        )
        let afterRegion = try glyphPagingRegionMetrics(
            glPixels: normalizedGLPixels,
            softwarePixels: normalizedSoftwarePixels,
            width: framebufferWidth,
            height: framebufferHeight,
            xRange: pageBoundary..<framebufferWidth
        )
        _ = try GLComparisonReport(
            scene: "glyphs_paged",
            width: context.width,
            height: context.height,
            difference: difference,
            tolerance: 4.0 / 255.0,
            glPixels: glPixels,
            softwarePixels: softwareContext.data
        )
        print(
            "GL_GLYPH_PAGING: maxTextureSize=\(maximumTextureSize) "
                + "glyphCount=\(glyphCount) pages=\(pages.count) difference=\(difference) "
                + "beforeGLPixels=\(beforeRegion.glNonBlackPixelCount) "
                + "beforeSoftwarePixels=\(beforeRegion.softwareNonBlackPixelCount) "
                + "beforeDifference=\(beforeRegion.difference) "
                + "afterGLPixels=\(afterRegion.glNonBlackPixelCount) "
                + "afterSoftwarePixels=\(afterRegion.softwareNonBlackPixelCount) "
                + "afterDifference=\(afterRegion.difference)"
        )
        #expect(difference <= 4.0 / 255.0, "Paged glyph rendering difference was \(difference)")
        #expect(beforeRegion.glNonBlackPixelCount > 0)
        #expect(beforeRegion.softwareNonBlackPixelCount > 0)
        #expect(beforeRegion.difference <= 4.0 / 255.0)
        #expect(afterRegion.glNonBlackPixelCount > 0)
        #expect(afterRegion.softwareNonBlackPixelCount > 0)
        #expect(afterRegion.difference <= 4.0 / 255.0)
    }

    /// Counts visible pixels and measures backend difference within one horizontal page region.
    /// - Parameters:
    ///   - glPixels: Normalized bottom-up GL RGBA bytes.
    ///   - softwarePixels: Normalized software RGBA bytes in matching coordinates.
    ///   - width: The actual framebuffer width.
    ///   - height: The actual framebuffer height.
    ///   - xRange: The horizontal region assigned to one side of the page boundary.
    /// - Returns: Non-black coverage in both backends and mean channel difference in the region.
    private func glyphPagingRegionMetrics(
        glPixels: Data,
        softwarePixels: Data,
        width: Int,
        height: Int,
        xRange: Range<Int>
    ) throws -> (glNonBlackPixelCount: Int, softwareNonBlackPixelCount: Int, difference: Double) {
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard width > 0,
              height > 0,
              pixelOverflow == false,
              byteOverflow == false,
              glPixels.count == byteCount,
              softwarePixels.count == byteCount,
              xRange.lowerBound >= 0,
              xRange.upperBound <= width,
              xRange.isEmpty == false else {
            throw GLComparisonReportError.invalidComparison
        }

        var glNonBlackPixelCount = 0
        var softwareNonBlackPixelCount = 0
        var channelDifference = 0
        for y in 0..<height {
            for x in xRange {
                let offset = (y * width + x) * 4
                let glIsVisible = glPixels[offset] > 8
                    || glPixels[offset + 1] > 8
                    || glPixels[offset + 2] > 8
                let softwareIsVisible = softwarePixels[offset] > 8
                    || softwarePixels[offset + 1] > 8
                    || softwarePixels[offset + 2] > 8
                if glIsVisible && glPixels[offset + 3] > 0 {
                    glNonBlackPixelCount += 1
                }
                if softwareIsVisible && softwarePixels[offset + 3] > 0 {
                    softwareNonBlackPixelCount += 1
                }
                for channel in 0..<4 {
                    channelDifference += abs(
                        Int(glPixels[offset + channel]) - Int(softwarePixels[offset + channel])
                    )
                }
            }
        }

        let regionPixelCount = (xRange.count * height)
        return (
            glNonBlackPixelCount,
            softwareNonBlackPixelCount,
            Double(channelDifference) / (Double(regionPixelCount) * 4 * 255)
        )
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

    /// Measures actual frame completion for repeated and changing text on the production GL path.
    /// - Parameter font: The bundled font fixture used for both measured workloads.
    private func measureCurrentPipelineFrameTimes(font: CGFont) throws {
        let frameCount = 30
        let warmupFrames = 10
        let repetitions = 5
        let glyphCount = 48
        let fontSize = 20.0
        let window: CGWindow
        do {
            window = try CGWindow(frame: CGRect(x: 0, y: 0, width: 512, height: 96), title: "Glyph frame benchmark")
        } catch let error as CGWindowError {
            print("GL_RUNNER_GRAPHICS_UNAVAILABLE: \(error)")
            throw error
        }

        let staticText = String(repeating: "IA", count: glyphCount / 2)
        let mutableTexts = (0..<frameCount).map { frame in
            String(repeating: "IA", count: glyphCount / 2 - 1)
                + (frame.isMultiple(of: 2) ? "IA" : "AI")
        }
        let staticFrame = try makeTimedGlyphFrame(staticText, font: font, fontSize: fontSize)
        let mutableFrames = try mutableTexts.map {
            try makeTimedGlyphFrame($0, font: font, fontSize: fontSize)
        }
        #expect(staticFrame.glyphs.count == glyphCount)
        #expect(mutableFrames.allSatisfy { $0.glyphs.count == glyphCount })
        #expect(mutableFrames.first?.glyphs != mutableFrames.last?.glyphs)

        let staticAtlasBytes = try atlasByteCount(for: staticFrame.glyphs, font: font, fontSize: fontSize)
        let mutableAtlasBytes = try Set(mutableFrames.map(\.glyphs)).reduce(into: [Int]()) { sizes, glyphs in
            sizes.append(try atlasByteCount(for: glyphs, font: font, fontSize: fontSize))
        }
        let glMetadata = try timedGLMetadata(for: window.cgContext)

        let staticTimings = try measureFrames(
            frames: Array(repeating: staticFrame, count: frameCount),
            context: window.cgContext,
            font: font,
            fontSize: fontSize,
            warmupFrames: warmupFrames,
            repetitions: repetitions
        )
        let mutableTimings = try measureFrames(
            frames: mutableFrames,
            context: window.cgContext,
            font: font,
            fontSize: fontSize,
            warmupFrames: warmupFrames,
            repetitions: repetitions
        )

        let rasterizations = frameCount * repetitions * glyphCount
        let frameCountMeasured = frameCount * repetitions
        let report = GlyphFrameTimeBenchmarkReport(
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.hostArchitecture,
            processorCount: ProcessInfo.processInfo.processorCount,
            glVendor: glMetadata.vendor,
            glRenderer: glMetadata.renderer,
            glVersion: glMetadata.version,
            framebufferWidth: window.cgContext.width,
            framebufferHeight: window.cgContext.height,
            msaaEnabled: glMetadata.msaaEnabled,
            samples: glMetadata.samples,
            fontFixture: "tiny-test.ttf",
            fontSizePixels: fontSize,
            glyphsPerFrame: glyphCount,
            frameCountPerScenarioPerRepetition: frameCount,
            warmupFramesPerScenario: warmupFrames,
            repetitions: repetitions,
            measuredFramesPerScenario: frameCountMeasured,
            timingScope: "wall-clock CPU submission through CGContext.flush() plus glad_glFinish() GPU completion; excludes buffer swap, v-sync, and presentation",
            uploadCountingMethod: "source-derived exact current path count, not GL-call interception",
            rasterizationCountingMethod: "glyph count submitted to production CGContext.showGlyphs; source path rasterizes each occurrence",
            synchronization: "glad_glFinish after every flushed frame",
            static: makeFrameScenarioReport(
                name: "static",
                timings: staticTimings,
                rasterizations: rasterizations,
                uploadCalls: frameCountMeasured,
                atlasByteCounts: [staticAtlasBytes]
            ),
            mutable: makeFrameScenarioReport(
                name: "mutable",
                timings: mutableTimings,
                rasterizations: rasterizations,
                uploadCalls: frameCountMeasured,
                atlasByteCounts: mutableAtlasBytes
            )
        )
        let data = try JSONEncoder.sorted.encode(report)
        let json = try #require(String(data: data, encoding: .utf8))
        try saveFrameTimeReport(data)
        print("GLYPH_REAL_FRAME_BENCHMARK: \(json)")
        #expect(report.static.measuredFrames == frameCountMeasured)
        #expect(report.mutable.measuredFrames == frameCountMeasured)
        #expect(report.static.medianNanoseconds > 0)
        #expect(report.mutable.medianNanoseconds > 0)
        #expect(report.static.uploadedBytes > 0)
        #expect(report.mutable.uploadedBytes > 0)
        #expect(report.static.uploadCalls == frameCountMeasured)
        #expect(report.mutable.uploadCalls == frameCountMeasured)
    }

    /// Resolves a deterministic text string into production glyph identifiers and positions.
    /// - Parameters:
    ///   - text: The text content for one frame.
    ///   - font: The bundled font fixture.
    ///   - fontSize: The rasterization height in pixels.
    /// - Returns: The immutable glyph sequence submitted for the frame.
    private func makeTimedGlyphFrame(
        _ text: String,
        font: CGFont,
        fontSize: Double
    ) throws -> TimedGlyphFrame {
        guard font.unitsPerEm > 0 else {
            throw GlyphFrameBenchmarkError.invalidFontMetrics
        }
        var glyphs: [CGGlyph] = []
        var positions: [OpenCoreGraphics.CGPoint] = []
        var penX = 0.0
        for character in text {
            let glyph = try #require(font.glyph(for: character))
            guard let advance = font.advance(for: glyph) else {
                throw GlyphFrameBenchmarkError.missingGlyphAdvance
            }
            glyphs.append(glyph)
            positions.append(OpenCoreGraphics.CGPoint(x: penX, y: 0))
            penX += advance * fontSize / Double(font.unitsPerEm)
        }
        return TimedGlyphFrame(glyphs: glyphs, positions: positions)
    }

    /// Measures only one-time atlas payload sizes for exact byte accounting.
    /// - Parameters:
    ///   - glyphs: The glyph sequence represented by the atlas.
    ///   - font: The bundled font fixture.
    ///   - fontSize: The rasterization height in pixels.
    /// - Returns: The packed R8 coverage payload size in bytes.
    private func atlasByteCount(for glyphs: [CGGlyph], font: CGFont, fontSize: Double) throws -> Int {
        let bitmaps = glyphs.map { font.rasterizedGlyph($0, at: fontSize) }
        return try #require(CGGlyphAtlas(bitmaps: bitmaps)?.coverage.count)
    }

    /// Captures the OpenGL driver and active framebuffer settings for the timing report.
    /// - Parameter context: The GL window context that will render the benchmark.
    /// - Returns: Driver identity and multisample configuration.
    private func timedGLMetadata(for context: CGContext) throws -> TimedGLMetadata {
        context.flush()
        var samples: GLint = 0
        glad_glGetIntegerv(GLenum(GL_SAMPLES), &samples)
        guard let version = glad_glGetString(GLenum(GL_VERSION)),
              let renderer = glad_glGetString(GLenum(GL_RENDERER)),
              let vendor = glad_glGetString(GLenum(GL_VENDOR)) else {
            throw GlyphFrameBenchmarkError.missingDriverMetadata
        }
        return TimedGLMetadata(
            vendor: String(cString: vendor),
            renderer: String(cString: renderer),
            version: String(cString: version),
            msaaEnabled: glad_glIsEnabled(GLenum(GL_MULTISAMPLE)) == GL_TRUE,
            samples: Int(samples)
        )
    }

    /// Measures wall-clock frame completion after warming the same GL context.
    /// - Parameters:
    ///   - frames: The prepared frames cycled through by the workload.
    ///   - context: The production window drawing context.
    ///   - font: The font to install into the context before timing.
    ///   - fontSize: The font rasterization height in pixels.
    ///   - warmupFrames: Untimed frames rendered before collecting samples.
    ///   - repetitions: Number of complete measured frame sequences.
    /// - Returns: One duration in nanoseconds for every completed measured frame.
    private func measureFrames(
        frames: [TimedGlyphFrame],
        context: CGContext,
        font: CGFont,
        fontSize: Double,
        warmupFrames: Int,
        repetitions: Int
    ) throws -> [Double] {
        context.setFont(font)
        context.setFontSize(fontSize)
        context.setCharacterSpacing(0)
        context.setBlendMode(.normal)

        for index in 0..<warmupFrames {
            drawTimedFrame(frames[index % frames.count], in: context)
        }

        var samples: [Double] = []
        samples.reserveCapacity(frames.count * repetitions)
        for _ in 0..<repetitions {
            for frame in frames {
                let clock = ContinuousClock()
                let start = clock.now
                drawTimedFrame(frame, in: context)
                let elapsed = start.duration(to: clock.now)
                samples.append(nanoseconds(in: elapsed))
            }
        }
        return samples
    }

    /// Submits one background and text frame, flushes it, and waits for GPU completion.
    /// - Parameters:
    ///   - frame: The text glyphs and positions to draw.
    ///   - context: The production window drawing context.
    private func drawTimedFrame(_ frame: TimedGlyphFrame, in context: CGContext) {
        context.setFillColor(.black)
        context.fill(CGRect(x: 0, y: 0, width: Double(context.width), height: Double(context.height)))
        context.setFillColor(.white)
        context.textPosition = OpenCoreGraphics.CGPoint(x: 8, y: 48)
        context.showGlyphs(frame.glyphs, at: frame.positions)
        context.flush()
        glad_glFinish()
    }

    /// Converts a monotonic duration to nanoseconds.
    /// - Parameter duration: The measured duration.
    /// - Returns: Nanoseconds elapsed.
    private func nanoseconds(in duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000_000_000
            + Double(components.attoseconds) / 1_000_000_000
    }

    /// Creates summary metrics without mixing CPU-cache prototype timings into real GL results.
    /// - Parameters:
    ///   - name: The workload name.
    ///   - timings: Per-frame wall-clock durations.
    ///   - rasterizations: Source-derived rasterization calls.
    ///   - uploadCalls: Source-derived GL texture uploads.
    ///   - atlasByteCounts: Exact preflight atlas payload sizes for each variant.
    /// - Returns: Per-frame distribution and logical memory/upload metrics.
    private func makeFrameScenarioReport(
        name: String,
        timings: [Double],
        rasterizations: Int,
        uploadCalls: Int,
        atlasByteCounts: [Int]
    ) -> GlyphFrameScenarioReport {
        let sorted = timings.sorted()
        let totalUploadedBytes = atlasByteCounts.reduce(0, +) * (timings.count / max(1, atlasByteCounts.count))
        return GlyphFrameScenarioReport(
            name: name,
            measuredFrames: timings.count,
            rasterizations: rasterizations,
            uploadCalls: uploadCalls,
            uploadedBytes: totalUploadedBytes,
            peakTransientAtlasBytes: atlasByteCounts.max() ?? 0,
            retainedGlyphCacheBytesAfterFlush: 0,
            minimumNanoseconds: sorted.first ?? 0,
            medianNanoseconds: sorted[sorted.count / 2],
            p95Nanoseconds: sorted[min(sorted.count - 1, (sorted.count * 95 + 99) / 100 - 1)],
            maximumNanoseconds: sorted.last ?? 0
        )
    }

    /// Persists the actual GL timing record alongside comparison artifacts when configured.
    /// - Parameter data: The encoded JSON report.
    private func saveFrameTimeReport(_ data: Data) throws {
        let output = URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_GL_ARTIFACTS"] ?? ".build/gl-comparison",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try data.write(to: output.appending(path: "glyph-frame-time.json"), options: .atomic)
    }

    /// Returns the architecture selected by the current Swift compilation target.
    private static var hostArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "other"
        #endif
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

/// Glyph identifiers and origins prepared for one measured frame.
private struct TimedGlyphFrame {
    /// Glyphs submitted to the production text drawing API.
    let glyphs: [CGGlyph]
    /// Text-space origins corresponding to the glyphs.
    let positions: [OpenCoreGraphics.CGPoint]
}

/// Driver metadata observed before the real GL timing run.
private struct TimedGLMetadata {
    /// OpenGL vendor string.
    let vendor: String
    /// OpenGL renderer string.
    let renderer: String
    /// OpenGL version string.
    let version: String
    /// Whether multisample rasterization is enabled.
    let msaaEnabled: Bool
    /// Active sample count reported by OpenGL.
    let samples: Int
}

/// JSON report combining the local machine, GL context and current-pipeline workloads.
private struct GlyphFrameTimeBenchmarkReport: Encodable {
    /// Operating system version string.
    let system: String
    /// Host CPU architecture.
    let architecture: String
    /// Available logical processors reported by ProcessInfo.
    let processorCount: Int
    /// OpenGL vendor string.
    let glVendor: String
    /// OpenGL renderer string.
    let glRenderer: String
    /// OpenGL version string.
    let glVersion: String
    /// Active framebuffer width in pixels.
    let framebufferWidth: Int
    /// Active framebuffer height in pixels.
    let framebufferHeight: Int
    /// Whether multisampling is enabled.
    let msaaEnabled: Bool
    /// Active sample count.
    let samples: Int
    /// Font resource used to prepare the workload.
    let fontFixture: String
    /// Glyph rasterization height in pixels.
    let fontSizePixels: Double
    /// Glyph occurrences submitted in each frame.
    let glyphsPerFrame: Int
    /// Measured workload frames per repetition.
    let frameCountPerScenarioPerRepetition: Int
    /// Untimed frames before sampling each scenario.
    let warmupFramesPerScenario: Int
    /// Number of measured repetitions for each scenario.
    let repetitions: Int
    /// Total number of timed frames per scenario.
    let measuredFramesPerScenario: Int
    /// Explicit operations included and excluded from each timed frame.
    let timingScope: String
    /// Basis used for the current pipeline's operation counters.
    let uploadCountingMethod: String
    /// Basis used for the source-derived rasterization counter.
    let rasterizationCountingMethod: String
    /// Synchronization operation used before stopping each frame timer.
    let synchronization: String
    /// Results for repeated unchanged text.
    let `static`: GlyphFrameScenarioReport
    /// Results for text whose glyph order changes between frames.
    let mutable: GlyphFrameScenarioReport
}

/// Timing distribution and source-derived metrics for one real GL workload.
private struct GlyphFrameScenarioReport: Encodable {
    /// Scenario identifier.
    let name: String
    /// Number of measured frames.
    let measuredFrames: Int
    /// Number of glyph rasterizations executed by the production path.
    let rasterizations: Int
    /// Number of texture uploads derived from the production path.
    let uploadCalls: Int
    /// R8 payload bytes derived from the production atlas payloads.
    let uploadedBytes: Int
    /// Largest one-frame atlas payload in bytes.
    let peakTransientAtlasBytes: Int
    /// Logical cache bytes after the existing path evicts the command atlas.
    let retainedGlyphCacheBytesAfterFlush: Int
    /// Fastest measured frame completion time in nanoseconds.
    let minimumNanoseconds: Double
    /// Median measured frame completion time in nanoseconds.
    let medianNanoseconds: Double
    /// 95th percentile frame completion time in nanoseconds.
    let p95Nanoseconds: Double
    /// Slowest measured frame completion time in nanoseconds.
    let maximumNanoseconds: Double
}

/// Errors for invalid benchmark fixture data or missing live GL metadata.
private enum GlyphFrameBenchmarkError: Error {
    /// The bundled font does not provide usable units-per-em metrics.
    case invalidFontMetrics
    /// The font does not provide an advance for a workload glyph.
    case missingGlyphAdvance
    /// The active OpenGL driver omitted required metadata.
    case missingDriverMetadata
}

/// Creates stable-key JSON encoding for reproducible benchmark artifacts.
private extension JSONEncoder {
    /// Encoder configured to sort object keys.
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
