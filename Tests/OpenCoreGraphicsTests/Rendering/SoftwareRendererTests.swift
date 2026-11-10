import Foundation
import Testing
@testable import OpenCoreGraphics

/// Tests exact pixel output from the bitmap software renderer.
struct SoftwareRendererTests {
    /// Verifies an aligned rectangle changes only its covered pixels.
    @Test
    func fillsExactlyTheRequestedPixels() throws {
        let context = try #require(makeContext())
        context.data = Data(repeating: 0, count: 8 * 8 * 4)
        context.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 2, y: 3, width: 3, height: 2))
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 2, y: 3, in: pixels) == [64, 128, 191, 255])
        #expect(pixel(at: 4, y: 4, in: pixels) == [64, 128, 191, 255])
        #expect(pixel(at: 1, y: 3, in: pixels) == [0, 0, 0, 0])
        #expect(pixel(at: 2, y: 5, in: pixels) == [0, 0, 0, 0])
    }

    /// Verifies a zero-blur shadow is displaced by the requested device-space offset.
    @Test
    func drawsShadowAtTheRequestedOffset() throws {
        let context = try #require(makeContext())
        context.data = Data(repeating: 0, count: 8 * 8 * 4)
        context.setShadow(offset: CGSize(width: 4, height: 4), blur: 0, color: .black)
        context.setFillColor(.white)
        context.fill(CGRect(x: 1, y: 1, width: 1, height: 1))
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 5, y: 5, in: pixels) == [0, 0, 0, 255])
        #expect(pixel(at: 1, y: 1, in: pixels) == [255, 255, 255, 255])
    }

    /// Verifies a 20-pixel TrueType glyph paints only within its expected bitmap bounds.
    @Test
    func drawsTrueTypeGlyphInsideItsExpectedBounds() throws {
        let context = try #require(makeContext(width: 32, height: 32))
        let fontURL = try #require(
            Bundle.module.url(forResource: "tiny-test", withExtension: "ttf", subdirectory: "Resources")
        )
        let font = try #require(CGFont(fontURL.path))
        let glyph = try #require(font.glyph(for: "I"))
        context.setFont(font)
        context.setFontSize(20)
        context.setTextDrawingMode(.stroke)
        context.setFillColor(.white)
        context.textPosition = CGPoint(x: 6, y: 8)
        context.showGlyphs([glyph], at: [.zero])
        context.flush()

        let pixels = Array(context.data)
        let painted = (0..<32).flatMap { y in
            (0..<32).compactMap { x -> (Int, Int)? in
                pixel(at: x, y: y, in: pixels, width: 32)[3] > 0 ? (x, y) : nil
            }
        }

        #expect(painted.isEmpty == false)
        #expect(painted.allSatisfy { (8..<15).contains($0.0) && (7..<23).contains($0.1) })
    }

    /// Verifies glyph origins account for character spacing and both text and context transforms.
    @Test
    func positionsGlyphsUsingTextStateAndTransforms() throws {
        let context = try #require(makeContext(width: 40, height: 64))
        let fontURL = try #require(
            Bundle.module.url(forResource: "tiny-test", withExtension: "ttf", subdirectory: "Resources")
        )
        let font = try #require(CGFont(fontURL.path))
        let glyph = try #require(font.glyph(for: "I"))
        context.setFont(font)
        context.setFontSize(20)
        context.setCharacterSpacing(5)
        context.textPosition = CGPoint(x: 2, y: 35)
        context.textMatrix = CGAffineTransform(a: 1.5, b: 0, c: 0, d: 1.5, tx: 1, ty: 0)
        context.translateBy(x: 2, y: 3)
        context.setFillColor(.white)
        context.showGlyphs([glyph, glyph], at: [.zero, .zero])
        context.flush()

        let pixels = Array(context.data)
        let painted = (0..<64).flatMap { y in
            (0..<40).compactMap { x -> (Int, Int)? in
                pixel(at: x, y: y, in: pixels, width: 40)[3] > 0 ? (x, y) : nil
            }
        }
        let paintedX = painted.map(\.0)
        let paintedY = painted.map(\.1)

        #expect(painted.isEmpty == false)
        #expect((paintedX.min() ?? 0) >= 10)
        #expect((paintedX.max() ?? 0) >= 18)
        #expect((paintedX.max() ?? 40) < 30)
        #expect((paintedY.min() ?? 0) >= 37)
        #expect((paintedY.max() ?? 64) < 60)
    }

    /// Verifies a black-to-white linear gradient produces evenly spaced pixel values.
    @Test
    func interpolatesLinearGradientAcrossPixelCenters() throws {
        let context = try #require(makeContext(width: 11, height: 1))
        let gradient = try #require(CGGradient(colors: [.black, .white], locations: [0, 1]))
        context.data = Data(repeating: 0, count: 11 * 4)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0.5, y: 0.5),
            end: CGPoint(x: 10.5, y: 0.5)
        )
        context.flush()

        let pixels = Array(context.data)
        let expected = [0, 26, 51, 77, 102, 128, 153, 179, 204, 230, 255]
        for (index, value) in expected.enumerated() {
            #expect(abs(Int(pixel(at: index, y: 0, in: pixels, width: 11)[0]) - value) <= 1)
        }
    }

    /// Verifies a radial gradient uses its ending radius and extends the last stop.
    @Test
    func interpolatesRadialGradientAndExtendsAfterEnd() throws {
        let context = try #require(makeContext(width: 9, height: 1))
        let gradient = try #require(CGGradient(colors: [.black, .white], locations: [0, 1]))
        context.data = Data(repeating: 0, count: 9 * 4)
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: 0.5, y: 0.5),
            startRadius: 0,
            endCenter: CGPoint(x: 0.5, y: 0.5),
            endRadius: 4,
            options: .drawsAfterEndLocation
        )
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 0, y: 0, in: pixels, width: 9) == [0, 0, 0, 255])
        #expect(pixel(at: 2, y: 0, in: pixels, width: 9) == [128, 128, 128, 255])
        #expect(pixel(at: 8, y: 0, in: pixels, width: 9) == [255, 255, 255, 255])
    }

    /// Verifies premultiplied source-over composition on an opaque white destination.
    @Test
    func compositesSourceOverWithPremultipliedChannels() throws {
        let context = try #require(makeContext())
        context.data = Data(repeating: 255, count: 8 * 8 * 4)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 1, y: 1, width: 2, height: 2))
        context.flush()

        #expect(pixel(at: 1, y: 1, in: Array(context.data)) == [255, 128, 128, 255])
    }

    /// Verifies clear fills transparent pixels and preserves pixels outside the rectangle.
    @Test
    func clearsOnlyTheRequestedPixels() throws {
        let context = try #require(makeContext())
        context.data = Data(repeating: 255, count: 8 * 8 * 4)
        context.clear(CGRect(x: 3, y: 2, width: 2, height: 3))
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 3, y: 2, in: pixels) == [0, 0, 0, 0])
        #expect(pixel(at: 4, y: 4, in: pixels) == [0, 0, 0, 0])
        #expect(pixel(at: 2, y: 2, in: pixels) == [255, 255, 255, 255])
    }

    /// Verifies every blend mode produces the expected result for a reference color pair.
    @Test(arguments: CGBlendMode.allCases)
    func compositesReferenceColorsUsingBlendMode(_ blendMode: CGBlendMode) throws {
        let context = try #require(makeContext(width: 1, height: 1))
        context.data = Data([153, 102, 51, 255])
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.setBlendMode(blendMode)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.flush()

        let actual = pixel(at: 0, y: 0, in: Array(context.data), width: 1)
        let expected = expectedPixel(for: blendMode)
        #expect(zip(actual, expected).allSatisfy { abs(Int($0.0) - Int($0.1)) <= 1 })
    }

    /// Verifies nearest-neighbor sampling preserves source pixels when an image is enlarged.
    @Test
    func scalesImageWithNearestNeighborSampling() throws {
        let context = try #require(makeContext(width: 4, height: 4))
        let image = makeImage(
            width: 2,
            height: 2,
            bytes: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255
            ]
        )
        context.data = Data(repeating: 0, count: 4 * 4 * 4)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 4))
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 0, y: 0, in: pixels, width: 4) == [0, 0, 255, 255])
        #expect(pixel(at: 3, y: 1, in: pixels, width: 4) == [255, 255, 255, 255])
        #expect(pixel(at: 1, y: 2, in: pixels, width: 4) == [255, 0, 0, 255])
        #expect(pixel(at: 3, y: 3, in: pixels, width: 4) == [0, 255, 0, 255])
    }

    /// Verifies image samples follow the inverse of a sheared current transform.
    @Test
    func samplesImageThroughInverseAffineTransform() throws {
        let context = try #require(makeContext(width: 4, height: 3))
        let image = makeImage(
            width: 2,
            height: 2,
            bytes: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255
            ]
        )
        context.data = Data(repeating: 0, count: 4 * 3 * 4)
        context.interpolationQuality = .none
        context.ctm = CGAffineTransform(a: 1, b: 0, c: 0.5, d: 1, tx: 0, ty: 0)
        context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 0, y: 1, in: pixels, width: 4) == [0, 0, 0, 0])
        #expect(pixel(at: 1, y: 1, in: pixels, width: 4) == [255, 0, 0, 255])
        #expect(pixel(at: 2, y: 1, in: pixels, width: 4) == [0, 255, 0, 255])
    }

    /// Verifies bilinear sampling combines neighboring pixels during enlargement.
    @Test
    func scalesImageWithBilinearSampling() throws {
        let context = try #require(makeContext(width: 4, height: 4))
        let image = makeImage(
            width: 2,
            height: 2,
            bytes: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255
            ]
        )
        context.data = Data(repeating: 0, count: 4 * 4 * 4)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 4))
        context.flush()

        #expect(pixel(at: 1, y: 1, in: Array(context.data), width: 4) == [96, 64, 191, 255])
    }

    /// Verifies bilinear interpolation avoids color fringes from transparent source pixels.
    @Test
    func interpolatesImageColorsInPremultipliedSpace() throws {
        let context = try #require(makeContext(width: 4, height: 1))
        let image = makeImage(
            width: 2,
            height: 1,
            bytes: [255, 0, 0, 0, 0, 0, 255, 255]
        )
        context.data = Data(repeating: 0, count: 4 * 4)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 1))
        context.flush()

        #expect(pixel(at: 1, y: 0, in: Array(context.data), width: 4) == [0, 0, 64, 64])
    }

    /// Verifies tiled drawing repeats source pixels across the destination quad.
    @Test
    func repeatsImagePixelsWhenTiling() throws {
        let context = try #require(makeContext(width: 4, height: 4))
        let image = makeImage(
            width: 2,
            height: 2,
            bytes: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255
            ]
        )
        context.data = Data(repeating: 0, count: 4 * 4 * 4)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 4), byTiling: true)
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 0, y: 0, in: pixels, width: 4) == [0, 0, 255, 255])
        #expect(pixel(at: 2, y: 0, in: pixels, width: 4) == [0, 0, 255, 255])
        #expect(pixel(at: 3, y: 0, in: pixels, width: 4) == [255, 255, 255, 255])
        #expect(pixel(at: 0, y: 1, in: pixels, width: 4) == [255, 0, 0, 255])
        #expect(pixel(at: 0, y: 2, in: pixels, width: 4) == [0, 0, 255, 255])
        #expect(pixel(at: 1, y: 3, in: pixels, width: 4) == [0, 255, 0, 255])
    }

    /// Verifies a curved outline produces full and fractional sample coverage.
    @Test
    func rasterizesCircleWithAntialiasedCoverage() throws {
        let context = try #require(makeContext(width: 20, height: 20))
        context.setFillColor(.black)
        context.beginPath()
        context.addPath(CGPath(ellipseIn: CGRect(x: 2, y: 2, width: 16, height: 16)))
        context.fillPath()
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 9, y: 9, in: pixels, width: 20)[3] == 255)
        let borderCoverage = pixel(at: 4, y: 4, in: pixels, width: 20)[3]
        #expect(borderCoverage > 0 && borderCoverage < 255)
    }

    /// Verifies winding and even-odd rules differ in the center of a five-point star.
    @Test(arguments: [CGPath.CGPathFillRule.winding, .evenOdd])
    func rasterizesStarUsingSelectedFillRule(rule: CGPath.CGPathFillRule) throws {
        let context = try #require(makeContext(width: 20, height: 20))
        context.setFillColor(.black)
        context.beginPath()
        context.addPath(fivePointStar())
        context.fillPath(using: rule)
        context.flush()

        let expectedAlpha: UInt8 = rule == .winding ? 255 : 0
        #expect(pixel(at: 9, y: 9, in: Array(context.data), width: 20)[3] == expectedAlpha)
    }

    /// Verifies a horizontal stroke of width four covers exactly four rows.
    @Test
    func rasterizesFourPixelWideHorizontalStroke() throws {
        let context = try #require(makeContext())
        context.setStrokeColor(.black)
        context.setLineWidth(4)
        context.beginPath()
        context.move(to: CGPoint(x: 0, y: 4))
        context.addLine(to: CGPoint(x: 8, y: 4))
        context.strokePath()
        context.flush()

        let pixels = Array(context.data)
        for y in 2..<6 {
            #expect(pixel(at: 4, y: y, in: pixels)[3] == 255)
        }
        #expect(pixel(at: 4, y: 1, in: pixels)[3] == 0)
        #expect(pixel(at: 4, y: 6, in: pixels)[3] == 0)
    }

    /// Verifies clip masks intersect and only render into their shared region.
    @Test
    func clipsFillToTheIntersectionOfClipPaths() throws {
        let context = try #require(makeContext())
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.beginPath()
        context.addRect(CGRect(x: 0, y: 0, width: 6, height: 6))
        context.clip()
        context.beginPath()
        context.addRect(CGRect(x: 0, y: 0, width: 4, height: 4))
        context.clip()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 3, y: 3, in: pixels)[3] == 255)
        #expect(pixel(at: 4, y: 3, in: pixels)[3] == 0)
        #expect(pixel(at: 3, y: 4, in: pixels)[3] == 0)
        #expect(pixel(at: 7, y: 7, in: pixels)[3] == 0)
    }

    /// Verifies rectangle clipping and resetClip restore the full bitmap region.
    @Test
    func clipsToPublicRectangleAndResetsTheClip() throws {
        let context = try #require(makeContext())
        let clipRect = CGRect(x: 2, y: 2, width: 4, height: 4)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.clip(to: clipRect)
        #expect(context.boundingBoxOfClipPath == clipRect)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))

        context.resetClip()
        #expect(context.boundingBoxOfClipPath == CGRect(x: 0, y: 0, width: 8, height: 8))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 7, y: 7, width: 1, height: 1))
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 1, y: 1, in: pixels)[3] == 0)
        #expect(pixel(at: 3, y: 3, in: pixels) == [255, 0, 0, 255])
        #expect(pixel(at: 7, y: 7, in: pixels) == [0, 0, 255, 255])
    }

    /// Verifies restoring graphics state restores the previous clipping mask.
    @Test
    func restoreGStateRestoresPreviousClipMask() throws {
        let context = try #require(makeContext())
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.beginPath()
        context.addRect(CGRect(x: 0, y: 0, width: 6, height: 6))
        context.clip()

        context.saveGState()
        context.beginPath()
        context.addRect(CGRect(x: 0, y: 0, width: 4, height: 4))
        context.clip()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        context.restoreGState()

        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        context.flush()

        let pixels = Array(context.data)
        #expect(pixel(at: 5, y: 5, in: pixels)[3] == 255)
        #expect(pixel(at: 6, y: 5, in: pixels)[3] == 0)
        #expect(pixel(at: 7, y: 7, in: pixels)[3] == 0)
    }

    /// Creates an 8×8 in-memory bitmap context.
    /// - Returns: The allocated bitmap context, or nil when creation fails.
    private func makeContext() -> CGContext? {
        makeContext(width: 8, height: 8)
    }

    /// Creates an in-memory bitmap context with the requested dimensions.
    /// - Parameters:
    ///   - width: The bitmap width in pixels.
    ///   - height: The bitmap height in pixels.
    /// - Returns: The allocated bitmap context, or nil when creation fails.
    private func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: .genericRGBLinear,
            bitmapInfo: 0
        )
    }

    /// Creates an 8-bit-per-component sRGB image with straight RGBA pixel data.
    /// - Parameters:
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    ///   - bytes: The tightly packed RGBA image data.
    /// - Returns: The image backed by the supplied bytes.
    private func makeImage(width: Int, height: Int, bytes: [UInt8]) -> CGImage {
        CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: .sRGB,
            bitmapInfo: .byteOrderDefault,
            provider: CGDataProvider(data: Data(bytes)),
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent,
            alphaInfo: .last
        )
    }

    /// Returns the reference RGBA output for one blend mode and the fixture colors.
    /// - Parameter blendMode: The blend mode under test.
    /// - Returns: The expected premultiplied pixel bytes.
    private func expectedPixel(for blendMode: CGBlendMode) -> [UInt8] {
        switch blendMode {
        case .normal, .copy, .sourceIn, .sourceAtop, .hue, .saturation, .color, .luminosity:
            [51, 128, 204, 255]
        case .multiply:
            [31, 51, 41, 255]
        case .screen:
            [173, 178, 214, 255]
        case .overlay:
            [92, 102, 82, 255]
        case .darken:
            [51, 102, 51, 255]
        case .lighten:
            [153, 128, 204, 255]
        case .colorDodge:
            [191, 204, 255, 255]
        case .colorBurn:
            [0, 0, 0, 255]
        case .softLight:
            [116, 102, 89, 255]
        case .hardLight:
            [61, 102, 173, 255]
        case .difference:
            [102, 26, 153, 255]
        case .exclusion:
            [143, 128, 173, 255]
        case .clear, .sourceOut, .destinationOut, .xor:
            [0, 0, 0, 0]
        case .destinationOver, .destinationIn, .destinationAtop:
            [153, 102, 51, 255]
        case .plusDarker:
            [0, 0, 0, 255]
        case .plusLighter:
            [204, 230, 255, 255]
        }
    }

    /// Creates a regular five-point star by connecting every second outer vertex.
    /// - Returns: The closed star path centered in a 20×20 destination.
    private func fivePointStar() -> CGPath {
        let center = CGPoint(x: 10, y: 10)
        let vertices: [OpenCoreGraphics.CGPoint] = (0..<5).map { index in
            let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / 5
            return CGPoint(x: center.x + 9 * cos(angle), y: center.y + 9 * sin(angle))
        }
        let order = [0, 2, 4, 1, 3]
        var path = CGPath()
        path.move(to: vertices[order[0]])
        for index in order.dropFirst() {
            path.addLine(to: vertices[index])
        }
        path.closeSubpath()
        return path
    }

    /// Returns the RGBA bytes at one pixel coordinate.
    /// - Parameters:
    ///   - x: The pixel column.
    ///   - y: The pixel row.
    ///   - pixels: The packed image bytes.
    ///   - width: The packed image width in pixels.
    /// - Returns: The four bytes at the requested coordinate.
    private func pixel(at x: Int, y: Int, in pixels: [UInt8], width: Int = 8) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(pixels[offset ..< offset + 4])
    }
}
