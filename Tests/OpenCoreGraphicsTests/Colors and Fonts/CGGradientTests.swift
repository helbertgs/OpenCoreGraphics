import Testing
@testable import OpenCoreGraphics

/// Tests validation and stored values for gradient color stops.
struct CGGradientTests {
    /// Verifies a valid ordered set of stops is preserved.
    @Test
    func storesValidColorStops() throws {
        let colors: [CGColor] = [.black, .white]
        let locations = [0.0, 1.0]
        let gradient = try #require(CGGradient(colors: colors, locations: locations))

        #expect(gradient.colors == colors)
        #expect(gradient.locations == locations)
    }

    /// Verifies malformed stop arrays and unsupported stop counts are rejected.
    @Test
    func rejectsInvalidColorStops() {
        #expect(CGGradient(colors: [.white], locations: [0]) == nil)
        #expect(CGGradient(colors: [.black, .white], locations: [0]) == nil)
        #expect(CGGradient(colors: [.black, .white], locations: [1, 0]) == nil)
        #expect(CGGradient(colors: [.black, .white], locations: [0, .infinity]) == nil)
        #expect(CGGradient(
            colors: Array(repeating: .black, count: CGGradient.maximumColorCount + 1),
            locations: Array(repeating: 0, count: CGGradient.maximumColorCount + 1)
        ) == nil)
    }
}
