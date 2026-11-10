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
            space: .sRGB,
            bitmapInfo: 0
        )
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
