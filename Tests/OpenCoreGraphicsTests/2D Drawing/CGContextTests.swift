import Testing
@testable import OpenCoreGraphics

struct CGContextTests {
    /// Verifies the initial values for every graphics-state parameter.
    @Test
    func defaultGraphicsStateMatchesCoreGraphicsValues() {
        let state = CGGraphicsState()

        #expect(state.ctm == .identity)
        #expect(state.fillColor == .black)
        #expect(state.strokeColor == .black)
        #expect(state.fillColorSpace == .genericRGBLinear)
        #expect(state.strokeColorSpace == .genericRGBLinear)
        #expect(state.lineWidth == 1)
        #expect(state.lineCap == .butt)
        #expect(state.lineJoin == .miter)
        #expect(state.miterLimit == 10)
        #expect(state.lineDash.isEmpty)
        #expect(state.blendMode == .normal)
        #expect(state.interpolationQuality == .default)
        #expect(state.renderingIntent == .defaultIntent)
        #expect(state.clip == nil)
        #expect(state.font == nil)
        #expect(state.fontSize == 12)
        #expect(state.characterSpacing == 0)
        #expect(state.textDrawingMode == .fill)
    }
}