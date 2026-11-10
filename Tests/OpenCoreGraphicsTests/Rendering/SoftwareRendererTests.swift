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

    /// Creates an 8×8 in-memory bitmap context.
    /// - Returns: The allocated bitmap context, or nil when creation fails.
    private func makeContext() -> CGContext? {
        CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: .sRGB,
            bitmapInfo: 0
        )
    }

    /// Returns the RGBA bytes at one pixel coordinate.
    /// - Parameters:
    ///   - x: The pixel column.
    ///   - y: The pixel row.
    ///   - pixels: The packed image bytes.
    /// - Returns: The four bytes at the requested coordinate.
    private func pixel(at x: Int, y: Int, in pixels: [UInt8]) -> [UInt8] {
        let offset = (y * 8 + x) * 4
        return Array(pixels[offset ..< offset + 4])
    }
}
