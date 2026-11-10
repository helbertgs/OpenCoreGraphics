import Testing
@testable import OpenCoreGraphics

struct CGColorSpaceTests {
    /// Verifies the name, model, and component count for every supported color space.
    @Test(arguments: [
        (space: CGColorSpace.sRGB, name: "sRGB", model: CGColorModel.rgb, componentCount: 3),
        (space: CGColorSpace.genericRGBLinear, name: "genericRGBLinear", model: CGColorModel.rgb, componentCount: 3),
        (space: CGColorSpace.genericCMYK, name: "genericCMYK", model: CGColorModel.cmyk, componentCount: 4),
        (space: CGColorSpace.linearGray, name: "linearGray", model: CGColorModel.gray, componentCount: 1)
    ])
    func colorSpaceMetadata(
        space: CGColorSpace,
        name: String,
        model: CGColorModel,
        componentCount: Int
    ) {
        #expect(space.name == name)
        #expect(space.model == model)
        #expect(space.numberOfComponents == componentCount)
    }
}
