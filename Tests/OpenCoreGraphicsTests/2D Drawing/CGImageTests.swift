import Foundation
import Testing
@testable import OpenCoreGraphics

struct CGImageTests {
    /// Verifies a one-pixel BMP is decoded into a complete RGBA bitmap.
    @Test
    func decodesOnePixelBMPToRGBA() throws {
        let url = try imageURL(named: "image-1x1")
        let image = try #require(CGImage(url: url.path))

        #expect(image.width == 1)
        #expect(image.height == 1)
        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
        #expect(image.bytesPerRow == 4)
        #expect(image.alphaInfo == .last)
        #expect(image.bitmapInfo == .byteOrder32Big)
        #expect(image.colorSpace == .sRGB)
        #expect(image.dataProvider?.data == Data([10, 20, 30, 255]))
    }

    /// Verifies a two-by-two BMP retains the row and pixel order when decoded.
    @Test
    func decodesTwoByTwoBMPToRGBA() throws {
        let url = try imageURL(named: "image-2x2")
        let image = try #require(CGImage(url: url.path))

        #expect(image.width == 2)
        #expect(image.height == 2)
        #expect(image.bytesPerRow == 8)
        #expect(image.dataProvider?.data == Data([
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 255, 255
        ]))
    }

    /// Verifies a missing image path returns nil instead of terminating the process.
    @Test
    func missingImageReturnsNil() {
        #expect(CGImage(url: "/path/that/does/not/exist.bmp") == nil)
    }

    /// Verifies image equality and hashing use object identity.
    @Test
    func imageEqualityUsesObjectIdentity() throws {
        let url = try imageURL(named: "image-1x1")
        let first = try #require(CGImage(url: url.path))
        let second = try #require(CGImage(url: url.path))

        #expect(first == first)
        #expect(first != second)
        #expect(Set([first, second]).count == 2)
    }

    /// Finds a named BMP in the test target's copied resource directory.
    /// - Parameter name: The resource's filename without its extension.
    /// - Returns: The URL of the bundled BMP, or nil if the test resource is missing.
    private func imageURL(named name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "bmp", subdirectory: "Resources"))
    }
}
