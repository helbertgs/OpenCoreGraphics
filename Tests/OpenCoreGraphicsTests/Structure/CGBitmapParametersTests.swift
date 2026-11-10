import Testing
@testable import OpenCoreGraphics

struct CGBitmapParametersTests {
    /// Verifies typed bitmap parameters can be initialized, read, and updated.
    @Test
    func bitmapParametersExposeTypedProperties() {
        var parameters = CGBitmapParameters(colorSpace: .genericRGBLinear)

        #expect(parameters.colorSpace == .genericRGBLinear)
        #expect(parameters.layout == .rgba)
        #expect(parameters.component == .integer8Bit)
        #expect(parameters.componentInfo == .integer)
        #expect(parameters.alphaInfo == .premultipliedLast)

        parameters.colorSpace = .genericCMYK
        parameters.layout = .bgra
        parameters.component = .float32Bit
        parameters.componentInfo = .float
        parameters.alphaInfo = .premultipliedFirst

        #expect(parameters.colorSpace == .genericCMYK)
        #expect(parameters.layout == .bgra)
        #expect(parameters.component == .float32Bit)
        #expect(parameters.componentInfo == .float)
        #expect(parameters.alphaInfo == .premultipliedFirst)
    }
}
