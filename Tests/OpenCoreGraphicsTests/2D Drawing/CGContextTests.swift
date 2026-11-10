import Testing
@testable import OpenCoreGraphics

struct CGContextTests {
    /// Verifies that restoring an empty graphics-state stack leaves state unchanged.
    @Test
    func restoreWithoutSaveLeavesGraphicsStateUnchanged() {
        let context = makeContext()
        context.translateBy(x: 4, y: 7)
        let originalTransform = context.ctm

        context.restoreGState()

        #expect(context.ctm == originalTransform)
    }

    /// Verifies nested graphics-state restoration without restoring the current path.
    @Test
    func nestedSaveAndRestorePreservesPathAndRestoresTransforms() {
        let context = makeContext()
        context.beginPath()
        context.move(to: CGPoint(x: 2, y: 3))
        let pathBeforeRestore = context.path

        context.translateBy(x: 1, y: 2)
        let firstTransform = context.ctm
        context.saveGState()

        context.scaleBy(x: 2, y: 3)
        let secondTransform = context.ctm
        context.saveGState()

        context.rotate(by: .pi / 4)
        let thirdTransform = context.ctm
        context.saveGState()
        context.translateBy(x: 8, y: 9)
        context.addLine(to: CGPoint(x: 5, y: 6))
        let pathAfterChanges = context.path

        context.restoreGState()
        #expect(context.ctm == thirdTransform)
        #expect(context.path == pathAfterChanges)
        #expect(context.path != pathBeforeRestore)

        context.restoreGState()
        #expect(context.ctm == secondTransform)
        #expect(context.path == pathAfterChanges)

        context.restoreGState()
        #expect(context.ctm == firstTransform)
        #expect(context.path == pathAfterChanges)
    }

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

    /// Creates a bitmap context for testing graphics-state behavior without a window.
    private func makeContext() -> CGContext {
        CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: .genericRGBLinear,
            bitmapInfo: 0
        )
    }
}