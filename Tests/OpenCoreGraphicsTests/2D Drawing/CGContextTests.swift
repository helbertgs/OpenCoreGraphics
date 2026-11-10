import Foundation
import Testing
@testable import OpenCoreGraphics

struct CGContextTests {
    /// Verifies the size-based initializer used for window drawing contexts.
    @Test
    func sizeInitializerStoresPixelDimensions() {
        let context = CGContext(width: 200, height: 100)

        #expect(context.width == 200)
        #expect(context.height == 100)
        #expect(context.bitsPerComponent == 8)
        #expect(context.bytesPerRow == 0)
    }

    /// Verifies software rendering converts sRGB fills and images into the bitmap color space.
    @Test
    func convertsSRGBFillsAndImagesToLinearBitmapPixels() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: .genericRGBLinear,
                bitmapInfo: 0
            )
        )
        let color = CGColor(sred: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.flush()
        #expect(Array(context.data.prefix(4)) == [55, 55, 55, 255])

        let image = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: .sRGB,
            bitmapInfo: .byteOrder32Big,
            provider: CGDataProvider(data: Data([128, 128, 128, 255])),
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        context.flush()

        #expect(Array(context.data.prefix(4)) == [55, 55, 55, 255])
    }

    /// Verifies software rendering encodes linear output for sRGB bitmap surfaces.
    @Test
    func encodesLinearColorsForSRGBBitmapPixels() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: .sRGB,
                bitmapInfo: 0
            )
        )
        let linearMidpoint = 0.21404114048223255
        context.setFillColor(CGColor(red: linearMidpoint, green: linearMidpoint, blue: linearMidpoint, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.flush()

        #expect(Array(context.data.prefix(4)) == [128, 128, 128, 255])
    }

    /// Verifies that restoring an empty graphics-state stack leaves state unchanged.
    @Test
    func restoreWithoutSaveLeavesGraphicsStateUnchanged() {
        let context = makeContext()
        context.translateBy(x: 4, y: 7)
        let originalTransform = context.ctm

        context.restoreGState()

        #expect(context.ctm == originalTransform)
    }

    /// Verifies nested graphics-state restoration without restoring the current path.
    @Test
    func nestedSaveAndRestorePreservesPathAndRestoresTransforms() {
        let context = makeContext()
        context.beginPath()
        context.move(to: CGPoint(x: 2, y: 3))
        let pathBeforeRestore = context.path

        context.translateBy(x: 1, y: 2)
        let firstTransform = context.ctm
        context.saveGState()

        context.scaleBy(x: 2, y: 3)
        let secondTransform = context.ctm
        context.saveGState()

        context.rotate(by: .pi / 4)
        let thirdTransform = context.ctm
        context.saveGState()
        context.translateBy(x: 8, y: 9)
        context.addLine(to: CGPoint(x: 5, y: 6))
        let pathAfterChanges = context.path

        context.restoreGState()
        #expect(context.ctm == thirdTransform)
        #expect(context.path == pathAfterChanges)
        #expect(context.path != pathBeforeRestore)

        context.restoreGState()
        #expect(context.ctm == secondTransform)
        #expect(context.path == pathAfterChanges)

        context.restoreGState()
        #expect(context.ctm == firstTransform)
        #expect(context.path == pathAfterChanges)
    }

    /// Verifies saved fonts survive overwriting their source files and restore exact glyph pixels.
    @Test
    func restoresNestedFontsAfterTheirSourceFilesAreOverwritten() throws {
        try verifiesNestedFontsSurviveSourceFileChanges(removingSourceFiles: false)
    }

    /// Verifies saved fonts survive removal of their source files and restore exact glyph pixels.
    @Test
    func restoresNestedFontsAfterTheirSourceFilesAreRemoved() throws {
        try verifiesNestedFontsSurviveSourceFileChanges(removingSourceFiles: true)
    }

    /// Verifies that all context transforms compose in the same order.
    @Test
    func transformMethodsComposeOnTheRight() {
        let context = makeContext()
        let translation = CGAffineTransform.translate(10, 20)
        let scaling = CGAffineTransform.scale(2, 3)
        let rotation = CGAffineTransform.rotate(.pi / 2)
        let concatenated = CGAffineTransform.translate(4, 5)

        context.translateBy(x: 10, y: 20)
        context.scaleBy(x: 2, y: 3)

        #expect(context.ctm == translation * scaling)
        #expect(CGPoint(x: 1, y: 1).applying(context.ctm) == CGPoint(x: 12, y: 23))

        context.rotate(by: .pi / 2)
        #expect(context.ctm == translation * scaling * rotation)

        context.concatenate(concatenated)
        #expect(context.ctm == translation * scaling * rotation * concatenated)
    }

    /// Verifies pixel-space coordinate conversions and inverse CTM behavior.
    @Test
    func coordinateConversionsUsePixelsAndRoundTrip() throws {
        let context = try #require(CGContext(
            data: nil,
            width: 200,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: .genericRGBLinear,
            bitmapInfo: 0
        ))
        let points = [
            CGPoint.zero,
            CGPoint(x: 200, y: 100),
            CGPoint(x: 12, y: 37),
            CGPoint(x: -5, y: 8),
            CGPoint(x: 72.5, y: 41.25)
        ]
        let transforms = [
            CGAffineTransform.identity,
            .translate(10, -5),
            .scale(2, 3),
            .rotate(.pi / 4)
        ]

        context.ctm = .identity
        #expect(context.convertToDeviceSpace(CGPoint(x: 200, y: 100)) == CGPoint(x: 200, y: 100))

        for transform in transforms {
            context.ctm = transform
            #expect(context.userSpaceToDeviceSpaceTransform == transform)

            for point in points {
                let devicePoint = context.convertToDeviceSpace(point)
                let userPoint = context.convertToUserSpace(devicePoint)
                #expect(abs(userPoint.x - point.x) < 1e-10)
                #expect(abs(userPoint.y - point.y) < 1e-10)
            }
        }

        context.ctm = .init(1) * .scale(2, 3) * .translate(10, -5)
        let userRect = CGRect(x: 2, y: 4, width: 8, height: 6)
        #expect(context.convertToUserSpace(context.convertToDeviceSpace(userRect)) == userRect)
        let userSize = CGSize(width: 8, height: 6)
        #expect(context.convertToUserSpace(context.convertToDeviceSpace(userSize)) == userSize)
    }

    /// Verifies an allocated bitmap context derives its row size and image metadata.
    @Test
    func bitmapContextAllocatesStorageAndCreatesImage() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: .sRGB,
                bitmapInfo: 0
            )
        )

        #expect(context.width == 2)
        #expect(context.height == 2)
        #expect(context.bitsPerComponent == 8)
        #expect(context.bitsPerPixel == 32)
        #expect(context.bytesPerRow == 8)
        #expect(context.alphaInfo == .premultipliedLast)
        #expect(context.data == Data(repeating: 0, count: 16))

        let image = try #require(context.makeImage())
        #expect(image.width == 2)
        #expect(image.height == 2)
        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
        #expect(image.bytesPerRow == 8)
        #expect(image.alphaInfo == .premultipliedLast)
        #expect(image.dataProvider?.data == context.data)
    }

    /// Verifies invalid bitmap dimensions, formats, and row layouts are rejected.
    @Test
    func rejectsInvalidBitmapContextParameters() {
        #expect(
            CGContext(
                data: nil,
                width: 0,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: .sRGB,
                bitmapInfo: 0
            ) == nil
        )
        #expect(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 16,
                bytesPerRow: 8,
                space: .sRGB,
                bitmapInfo: 0
            ) == nil
        )
        #expect(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 7,
                space: .sRGB,
                bitmapInfo: 0
            ) == nil
        )
        #expect(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: .genericCMYK,
                bitmapInfo: 0
            ) == nil
        )
        #expect(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: .sRGB,
                bitmapInfo: -1
            ) == nil
        )
    }

    /// Verifies a bitmap context borrows caller memory and snapshots it into images.
    @Test
    func bitmapContextUsesBorrowedMemoryAndCopiesImages() throws {
        var storage = [UInt8](repeating: 0, count: 16)
        try storage.withUnsafeMutableBufferPointer { buffer in
            let pointer = try #require(buffer.baseAddress)
            let context = try #require(
                CGContext(
                    data: UnsafeMutableRawPointer(pointer),
                    width: 2,
                    height: 2,
                    bitsPerComponent: 8,
                    bytesPerRow: 8,
                    space: .sRGB,
                    bitmapInfo: 0
                )
            )
            buffer[0] = 10
            buffer[1] = 20
            buffer[2] = 30
            buffer[3] = 40
            #expect(context.data == Data(buffer))

            let image = try #require(context.makeImage())
            buffer[0] = 99

            #expect(context.data[0] == 99)
            #expect(image.dataProvider?.data?[0] == 10)
            #expect(image.alphaInfo == .premultipliedLast)
        }
    }

    /// Verifies little-endian bitmap contexts infer BGRA alpha-first metadata.
    @Test
    func infersBGRAFormatFromLittleEndianBitmapInfo() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: .sRGB,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
            )
        )

        #expect(context.bitmapInfo == .byteOrder32Little)
        #expect(context.alphaInfo == .premultipliedFirst)
        #expect(context.makeImage()?.alphaInfo == .premultipliedFirst)

        let opaqueContext = try #require(
            CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: .sRGB,
                bitmapInfo: 6
            )
        )
        #expect(opaqueContext.alphaInfo == .noneSkipFirst)
        #expect(opaqueContext.makeImage()?.alphaInfo == .noneSkipFirst)
    }

    /// Verifies that every curve and arc method applies the context transform.
    @Test
    func pathCurvesAndArcsApplyCurrentTransform() throws {
        let context = makeContext()
        context.beginPath()
        context.scaleBy(x: 2, y: 2)

        context.addArc(center: .zero, radius: 5, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        let arcPath = try #require(context.path)
        #expect(arcPath.subpath.first?.points == [CGPoint(x: 10, y: 0)])
        #expect(abs(arcPath.currentPoint.x) < 1e-10)
        #expect(abs(arcPath.currentPoint.y - 10) < 1e-10)

        context.beginPath()
        context.move(to: CGPoint(x: 1, y: 1))
        context.addArc(tangent1End: CGPoint(x: 3, y: 1), tangent2End: CGPoint(x: 3, y: 4), radius: 1)
        #expect(abs((context.path?.currentPoint.x ?? 0) - 6) < 1e-6)
        #expect(abs((context.path?.currentPoint.y ?? 0) - 4) < 1e-6)
        #expect(context.path?.subpath.last?.type == .addCurveToPoint)

        context.beginPath()
        context.move(to: CGPoint(x: 1, y: 1))
        context.addCurve(
            to: CGPoint(x: 4, y: 5),
            control1: CGPoint(x: 2, y: 3),
            control2: CGPoint(x: 3, y: 4)
        )
        #expect(context.path?.subpath.last?.points == [
            CGPoint(x: 2, y: 2),
            CGPoint(x: 4, y: 6),
            CGPoint(x: 6, y: 8),
            CGPoint(x: 8, y: 10)
        ])

        context.beginPath()
        context.move(to: CGPoint(x: 1, y: 1))
        context.addQuadCurve(to: CGPoint(x: 4, y: 5), control: CGPoint(x: 2, y: 3))
        #expect(context.path?.subpath.last?.points == [
            CGPoint(x: 2, y: 2),
            CGPoint(x: 4, y: 6),
            CGPoint(x: 8, y: 10)
        ])
    }

    /// Verifies the initial values for every graphics-state parameter.
    @Test
    func defaultGraphicsStateMatchesCoreGraphicsValues() {
        let state = CGGraphicsState()

        #expect(state.ctm == .identity)
        #expect(state.fillColor == .black)
        #expect(state.strokeColor == .black)
        #expect(state.fillColorSpace == .genericRGBLinear)
        #expect(state.strokeColorSpace == .genericRGBLinear)
        #expect(state.lineWidth == 1)
        #expect(state.lineCap == .butt)
        #expect(state.lineJoin == .miter)
        #expect(state.miterLimit == 10)
        #expect(state.lineDash.isEmpty)
        #expect(state.lineDashPhase == 0)
        #expect(state.blendMode == .normal)
        #expect(state.interpolationQuality == .default)
        #expect(state.renderingIntent == .defaultIntent)
        #expect(state.clip == nil)
        #expect(state.font == nil)
        #expect(state.fontSize == 12)
        #expect(state.characterSpacing == 0)
        #expect(state.textDrawingMode == .fill)
    }

    /// Checks three saved fonts against pixel baselines after their backing files change.
    private func verifiesNestedFontsSurviveSourceFileChanges(removingSourceFiles: Bool) throws {
        let bundledFontURL = try #require(
            Bundle.module.url(forResource: "tiny-test", withExtension: "ttf", subdirectory: "Resources")
        )
        let fileManager = FileManager.default
        let sourceData = try Data(contentsOf: bundledFontURL)
        let fontURLs = (0..<3).map { _ in
            fileManager.temporaryDirectory.appending(path: "\(UUID().uuidString).ttf")
        }
        defer {
            for url in fontURLs {
                try? fileManager.removeItem(at: url)
            }
        }

        for url in fontURLs {
            try fileManager.copyItem(at: bundledFontURL, to: url)
        }

        let firstFont = try #require(CGFont(fontURLs[0].path))
        let secondFont = try #require(CGFont(fontURLs[1].path))
        let thirdFont = try #require(CGFont(fontURLs[2].path))
        let firstGlyph = try #require(firstFont.glyph(for: "A"))
        let secondGlyph = try #require(secondFont.glyph(for: "A"))
        let thirdGlyph = try #require(thirdFont.glyph(for: "A"))
        let firstSize = 12.0
        let secondSize = 18.0
        let thirdSize = 24.0
        let glyphPosition = OpenCoreGraphics.CGPoint(x: 8, y: 40)
        let firstPixels = try renderedGlyphPixels(
            font: firstFont,
            size: firstSize,
            glyph: firstGlyph,
            at: glyphPosition
        )
        let secondPixels = try renderedGlyphPixels(
            font: secondFont,
            size: secondSize,
            glyph: secondGlyph,
            at: glyphPosition
        )
        let thirdPixels = try renderedGlyphPixels(
            font: thirdFont,
            size: thirdSize,
            glyph: thirdGlyph,
            at: glyphPosition
        )
        #expect(firstPixels != Data(repeating: 0, count: firstPixels.count))
        #expect(firstPixels != secondPixels)
        #expect(secondPixels != thirdPixels)

        let context = try makeFontBitmapContext()
        context.saveGState()
        context.setFont(firstFont)
        context.setFontSize(firstSize)
        context.saveGState()
        context.setFont(secondFont)
        context.setFontSize(secondSize)
        context.saveGState()
        context.setFont(thirdFont)
        context.setFontSize(thirdSize)
        context.saveGState()
        context.setFont(firstFont)
        context.setFontSize(32)

        for url in fontURLs {
            if removingSourceFiles {
                try fileManager.removeItem(at: url)
            } else {
                try Data(repeating: 0, count: sourceData.count).write(to: url, options: .atomic)
            }
        }

        context.restoreGState()
        context.data = Data(repeating: 0, count: context.bytesPerRow * context.height)
        context.showGlyphs([thirdGlyph], at: [glyphPosition])
        context.flush()
        #expect(context.data == thirdPixels)

        context.restoreGState()
        context.data = Data(repeating: 0, count: context.bytesPerRow * context.height)
        context.showGlyphs([secondGlyph], at: [glyphPosition])
        context.flush()
        #expect(context.data == secondPixels)

        context.restoreGState()
        context.data = Data(repeating: 0, count: context.bytesPerRow * context.height)
        context.showGlyphs([firstGlyph], at: [glyphPosition])
        context.flush()
        #expect(context.data == firstPixels)

        let emptyPixels = Data(repeating: 0, count: context.bytesPerRow * context.height)
        context.restoreGState()
        context.data = emptyPixels
        context.showGlyphs([firstGlyph], at: [glyphPosition])
        context.flush()
        #expect(context.data == emptyPixels)

        context.restoreGState()
        context.data = emptyPixels
        context.showGlyphs([firstGlyph], at: [glyphPosition])
        context.flush()
        #expect(context.data == emptyPixels)
    }

    /// Renders one glyph to a transparent bitmap and returns the complete pixel buffer.
    private func renderedGlyphPixels(
        font: CGFont,
        size: Double,
        glyph: CGGlyph,
        at position: OpenCoreGraphics.CGPoint
    ) throws -> Data {
        let context = try makeFontBitmapContext()
        context.setFont(font)
        context.setFontSize(size)
        context.showGlyphs([glyph], at: [position])
        context.flush()
        return context.data
    }

    /// Creates an allocated bitmap context for exact glyph-pixel comparisons.
    private func makeFontBitmapContext() throws -> CGContext {
        let context = try #require(
            CGContext(
                data: nil,
                width: 64,
                height: 64,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: .genericRGBLinear,
                bitmapInfo: 0
            )
        )
        context.setFillColor(.black)
        return context
    }

    /// Creates a bitmap context for testing graphics-state behavior without a window.
    private func makeContext() -> CGContext {
        CGContext(width: 64, height: 64)
    }
}