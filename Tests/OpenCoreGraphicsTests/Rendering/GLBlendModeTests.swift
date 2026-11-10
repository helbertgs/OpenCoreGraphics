import Testing
@testable import OpenCoreGraphics

/// Verifies OpenGL blend factors and fallback coverage without requiring a graphics context.
struct GLBlendModeTests {
    /// Verifies every Core Graphics blend mode is either mapped directly or documented as a fallback.
    @Test
    func classifiesEveryBlendMode() {
        let directlyMapped: Set<CGBlendMode> = [
            .normal,
            .screen,
            .clear,
            .copy,
            .sourceIn,
            .sourceOut,
            .sourceAtop,
            .destinationOver,
            .destinationIn,
            .destinationOut,
            .destinationAtop,
            .xor,
            .plusLighter
        ]
        let fallbackModes: Set<CGBlendMode> = [
            .multiply,
            .overlay,
            .darken,
            .lighten,
            .colorDodge,
            .colorBurn,
            .softLight,
            .hardLight,
            .difference,
            .exclusion,
            .hue,
            .saturation,
            .color,
            .luminosity,
            .plusDarker
        ]

        #expect(directlyMapped.union(fallbackModes) == Set(CGBlendMode.allCases))
        #expect(directlyMapped.isDisjoint(with: fallbackModes))
        #expect(directlyMapped.allSatisfy {
            GLBlendModeMapper.configuration(for: $0).fallsBackToNormal == false
        })
        #expect(fallbackModes.allSatisfy {
            GLBlendModeMapper.configuration(for: $0).fallsBackToNormal
        })
    }

    /// Verifies normal, screen, and Porter-Duff modes use premultiplied factors.
    @Test
    func mapsPremultipliedBlendFactors() {
        #expect(GLBlendModeMapper.configuration(for: .normal) == .normal())
        #expect(
            GLBlendModeMapper.configuration(for: .screen) == GLBlendConfiguration(
                sourceRGB: .oneMinusDestinationColor,
                destinationRGB: .one,
                sourceAlpha: .one,
                destinationAlpha: .oneMinusSourceAlpha
            )
        )
        #expect(
            GLBlendModeMapper.configuration(for: .sourceIn) == GLBlendConfiguration(
                sourceRGB: .destinationAlpha,
                destinationRGB: .zero,
                sourceAlpha: .destinationAlpha,
                destinationAlpha: .zero
            )
        )
        #expect(
            GLBlendModeMapper.configuration(for: .xor) == GLBlendConfiguration(
                sourceRGB: .oneMinusDestinationAlpha,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .oneMinusDestinationAlpha,
                destinationAlpha: .oneMinusSourceAlpha
            )
        )
    }
}
