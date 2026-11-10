import Testing
@testable import OpenCoreGraphics

/// Tests pixel-surface ownership, layout validation, and row-aware access.
struct PixelSurfaceTests {
    /// Verifies a surface borrows caller memory and honors row padding.
    @Test
    func writesPixelsIntoBorrowedMemoryWithPaddedRows() throws {
        let bytesPerRow = 24
        var storage = [UInt8](repeating: 0, count: bytesPerRow * 4)
        try storage.withUnsafeMutableBufferPointer { buffer in
            let pointer = try #require(buffer.baseAddress)
            let surface = try #require(
                PixelSurface(
                    data: UnsafeMutableRawPointer(pointer),
                    width: 4,
                    height: 4,
                    bytesPerRow: bytesPerRow,
                    colorSpace: .sRGB,
                    alphaInfo: .premultipliedLast,
                    bitmapInfo: .byteOrderDefault
                )
            )
            let pixel = PixelSurface.Pixel(red: 10, green: 20, blue: 30, alpha: 40)

            #expect(surface.setPixel(pixel, x: 2, y: 1))
            #expect(surface.pixel(x: 2, y: 1) == pixel)
            #expect(Array(buffer[bytesPerRow + 8 ..< bytesPerRow + 12]) == [10, 20, 30, 40])
            #expect(buffer[bytesPerRow - 1] == 0)
        }
    }

    /// Verifies the owned allocation is zeroed and accepts reads and writes.
    @Test
    func allocatesAndInitializesOwnedMemory() throws {
        let surface = try #require(
            PixelSurface(
                data: nil,
                width: 2,
                height: 2,
                bytesPerRow: 8,
                colorSpace: .genericRGBLinear,
                alphaInfo: .premultipliedLast,
                bitmapInfo: .byteOrder32Big
            )
        )

        #expect(surface.pixel(x: 0, y: 0) == PixelSurface.Pixel(red: 0, green: 0, blue: 0, alpha: 0))
        #expect(surface.setPixel(PixelSurface.Pixel(red: 4, green: 5, blue: 6, alpha: 7), x: 1, y: 1))
        #expect(surface.pixel(x: 1, y: 1) == PixelSurface.Pixel(red: 4, green: 5, blue: 6, alpha: 7))
    }

    /// Verifies little-endian first-alpha storage maps to BGRA bytes.
    @Test
    func readsAndWritesLittleEndianBGRA() throws {
        let surface = try #require(
            PixelSurface(
                data: nil,
                width: 1,
                height: 1,
                bytesPerRow: 4,
                colorSpace: .sRGB,
                alphaInfo: .premultipliedFirst,
                bitmapInfo: .byteOrder32Little
            )
        )
        let pixel = PixelSurface.Pixel(red: 1, green: 2, blue: 3, alpha: 4)

        #expect(surface.setPixel(pixel, x: 0, y: 0))
        #expect(Array(UnsafeBufferPointer(start: surface.dataPointer.assumingMemoryBound(to: UInt8.self), count: 4)) == [3, 2, 1, 4])
        #expect(surface.pixel(x: 0, y: 0) == pixel)
    }

    /// Verifies unsupported color spaces and bitmap layouts are rejected.
    @Test
    func rejectsUnsupportedSurfaceFormats() {
        #expect(
            PixelSurface(
                data: nil,
                width: 4,
                height: 4,
                bytesPerRow: 16,
                colorSpace: .genericCMYK,
                alphaInfo: .premultipliedLast,
                bitmapInfo: .byteOrderDefault
            ) == nil
        )
        #expect(
            PixelSurface(
                data: nil,
                width: 4,
                height: 4,
                bytesPerRow: 16,
                colorSpace: .sRGB,
                alphaInfo: .premultipliedLast,
                bitmapInfo: .byteOrder32Little
            ) == nil
        )
        #expect(
            PixelSurface(
                data: nil,
                width: 4,
                height: 4,
                bytesPerRow: 15,
                colorSpace: .sRGB,
                alphaInfo: .premultipliedLast,
                bitmapInfo: .byteOrderDefault
            ) == nil
        )
    }

    /// Verifies opaque formats ignore alpha storage and report full opacity.
    @Test
    func treatsSkippedChannelsAsOpaque() throws {
        let surface = try #require(
            PixelSurface(
                data: nil,
                width: 1,
                height: 1,
                bytesPerRow: 4,
                colorSpace: .sRGB,
                alphaInfo: .noneSkipFirst,
                bitmapInfo: .byteOrder32Little
            )
        )
        let pixel = PixelSurface.Pixel(red: 10, green: 20, blue: 30, alpha: 0)

        #expect(surface.setPixel(pixel, x: 0, y: 0))
        #expect(surface.pixel(x: 0, y: 0) == PixelSurface.Pixel(red: 10, green: 20, blue: 30, alpha: 255))
        #expect(Array(UnsafeBufferPointer(start: surface.dataPointer.assumingMemoryBound(to: UInt8.self), count: 4)) == [30, 20, 10, 255])

        let rgbaSurface = try #require(
            PixelSurface(
                data: nil,
                width: 1,
                height: 1,
                bytesPerRow: 4,
                colorSpace: .sRGB,
                alphaInfo: .noneSkipLast,
                bitmapInfo: .byteOrderDefault
            )
        )
        #expect(rgbaSurface.setPixel(pixel, x: 0, y: 0))
        #expect(rgbaSurface.pixel(x: 0, y: 0) == PixelSurface.Pixel(red: 10, green: 20, blue: 30, alpha: 255))
        #expect(Array(UnsafeBufferPointer(start: rgbaSurface.dataPointer.assumingMemoryBound(to: UInt8.self), count: 4)) == [10, 20, 30, 255])
    }
}
