import Foundation
import Testing
@testable import OpenCoreGraphics

/// Tests color construction, copying, and system color values.
struct CGColorTests {
    /// Verifies the constructors and system colors preserve their components.
    @Test
    func colorConstructorsAndSystemValues() {
        let rgb = CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        let srgb = CGColor(sred: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        let gray = CGColor(gray: 0.5, alpha: 0.6)
        let cmyk = CGColor(cyan: 0.1, magenta: 0.2, yellow: 0.3, black: 0.4, alpha: 0.5)

        #expect(rgb.colorSpace == .genericRGBLinear)
        #expect(rgb.components == [0.1, 0.2, 0.3, 0.4])
        #expect(srgb.colorSpace == .sRGB)
        #expect(srgb.components == [0.1, 0.2, 0.3, 0.4])
        #expect(gray.colorSpace == .linearGray)
        #expect(gray.components == [0.5, 0.6])
        #expect(cmyk.colorSpace == .genericCMYK)
        #expect(cmyk.components == [0.1, 0.2, 0.3, 0.4, 0.5])
        #expect(CGColor.black.alpha == 1)
        #expect(CGColor.white.components == [1, 1, 1, 1])
        #expect(CGColor.clear.alpha == 0)
    }

    /// Verifies color copies retain components and can replace alpha.
    @Test
    func copyPreservesComponentsAndReplacesAlpha() throws {
        let color = CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let copy = try #require(color.copy())
        let faded = try #require(color.copy(alpha: 0.25))
        let componentsCopy = try #require(CGColor(colorSpace: .sRGB, components: [0.1, 0.2, 0.3, 0.4]))
        let emptyComponents = try #require(CGColor(colorSpace: .linearGray, components: []))

        #expect(copy == color)
        #expect(faded.components == [0.2, 0.4, 0.6, 0.25])
        #expect(componentsCopy.alpha == 0.4)
        #expect(emptyComponents.alpha == 1)
        #expect(color.numberOfComponents == 4)
        #expect(color.description == "CGColor(colorSpace: CGColorSpace.genericRGBLinear, components: [0.2, 0.4, 0.6, 0.8], alpha: 0.8)")
    }

    /// Verifies sRGB values convert to linear RGB and back without changing alpha.
    @Test
    func convertsBetweenSRGBAndLinearRGB() throws {
        let linear = try #require(
            CGColor(sred: 0.5, green: 0.5, blue: 0.5, alpha: 0.25)
                .converted(to: .genericRGBLinear)
        )
        let srgb = try #require(linear.converted(to: .sRGB))

        #expect(linear.colorSpace == .genericRGBLinear)
        #expect(abs(linear.components[0] - 0.2140) < 0.001)
        #expect(linear.alpha == 0.25)
        #expect(srgb.colorSpace == .sRGB)
        #expect(abs(srgb.components[0] - 0.5) < 0.001)
        #expect(srgb.alpha == 0.25)
    }

    /// Verifies copying a decoded color with no color space returns nil safely.
    @Test
    func copyWithoutColorSpaceReturnsNil() throws {
        let data = Data(#"{"alpha":1,"colorSpace":null,"components":[0,0,0,1]}"#.utf8)
        let color = try JSONDecoder().decode(CGColor.self, from: data)

        #expect(color.copy() == nil)
        #expect(color.copy(alpha: 0.5) == nil)
    }
}
