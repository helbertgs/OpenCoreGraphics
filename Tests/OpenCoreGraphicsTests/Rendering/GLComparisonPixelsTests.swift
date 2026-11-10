import Foundation
import Testing

/// Tests conversion of framebuffer bytes without a graphics context.
struct GLComparisonPixelsTests {
    /// Linear RGB is encoded to sRGB while alpha and row order remain unchanged.
    @Test
    private func convertsLinearPixels() throws {
        let raw = Data([0, 128, 255, 255, 64, 32, 16, 255])
        let result = try GLComparisonPixels(pixels: raw, storedAsSRGB: false)
        #expect(result.data == Data([0, 188, 255, 255, 137, 99, 71, 255]))
    }

    /// Already encoded pixels are not converted a second time.
    @Test
    private func preservesEncodedPixels() throws {
        let raw = Data([0, 128, 255, 255])
        #expect(try GLComparisonPixels(pixels: raw, storedAsSRGB: true).data == raw)
    }

    /// Rejects empty, incomplete or nonopaque buffers instead of producing misleading comparisons.
    @Test
    private func rejectsInvalidPixels() {
        for raw in [Data(), Data([1]), Data([1, 2, 3, 0])] {
            #expect(throws: GLComparisonPixelsError.invalidOpaquePixels) {
                try GLComparisonPixels(pixels: raw, storedAsSRGB: false)
            }
        }
    }
}
