@preconcurrency import OpenGLAD

/// A blend factor used by an OpenGL blend configuration.
enum GLBlendFactor: Equatable, Sendable {
    /// Multiplies the source or destination by zero.
    case zero

    /// Leaves the source or destination unchanged.
    case one

    /// Multiplies a component by the source alpha.
    case sourceAlpha

    /// Multiplies a component by one minus the source alpha.
    case oneMinusSourceAlpha

    /// Multiplies a component by the destination alpha.
    case destinationAlpha

    /// Multiplies a component by one minus the destination alpha.
    case oneMinusDestinationAlpha

    /// Multiplies a color component by one minus the destination color.
    case oneMinusDestinationColor

    /// The OpenGL constant representing this factor.
    var openGLValue: GLenum {
        switch self {
        case .zero:
            GLenum(GL_ZERO)
        case .one:
            GLenum(GL_ONE)
        case .sourceAlpha:
            GLenum(GL_SRC_ALPHA)
        case .oneMinusSourceAlpha:
            GLenum(GL_ONE_MINUS_SRC_ALPHA)
        case .destinationAlpha:
            GLenum(GL_DST_ALPHA)
        case .oneMinusDestinationAlpha:
            GLenum(GL_ONE_MINUS_DST_ALPHA)
        case .oneMinusDestinationColor:
            GLenum(GL_ONE_MINUS_DST_COLOR)
        }
    }
}

/// The separate RGB and alpha factors needed to composite a batch.
struct GLBlendConfiguration: Equatable, Sendable {
    /// The factor applied to source RGB components.
    let sourceRGB: GLBlendFactor

    /// The factor applied to destination RGB components.
    let destinationRGB: GLBlendFactor

    /// The factor applied to source alpha.
    let sourceAlpha: GLBlendFactor

    /// The factor applied to destination alpha.
    let destinationAlpha: GLBlendFactor

    /// Whether this configuration deliberately falls back to normal blending.
    let fallsBackToNormal: Bool

    /// Creates a configuration with separate factors for color and alpha.
    /// - Parameters:
    ///   - sourceRGB: The source color factor.
    ///   - destinationRGB: The destination color factor.
    ///   - sourceAlpha: The source alpha factor.
    ///   - destinationAlpha: The destination alpha factor.
    ///   - fallsBackToNormal: Whether the requested mode uses normal blending instead.
    init(
        sourceRGB: GLBlendFactor,
        destinationRGB: GLBlendFactor,
        sourceAlpha: GLBlendFactor,
        destinationAlpha: GLBlendFactor,
        fallsBackToNormal: Bool = false
    ) {
        self.sourceRGB = sourceRGB
        self.destinationRGB = destinationRGB
        self.sourceAlpha = sourceAlpha
        self.destinationAlpha = destinationAlpha
        self.fallsBackToNormal = fallsBackToNormal
    }

    /// Creates the premultiplied source-over configuration.
    /// - Parameter fallsBackToNormal: Whether this is a fallback for another mode.
    /// - Returns: The normal source-over blend configuration.
    static func normal(fallsBackToNormal: Bool = false) -> GLBlendConfiguration {
        GLBlendConfiguration(
            sourceRGB: .one,
            destinationRGB: .oneMinusSourceAlpha,
            sourceAlpha: .one,
            destinationAlpha: .oneMinusSourceAlpha,
            fallsBackToNormal: fallsBackToNormal
        )
    }
}

/// Maps Core Graphics compositing modes to premultiplied OpenGL blend factors.
enum GLBlendModeMapper {
    /// Returns the direct OpenGL mapping or the documented normal-mode fallback.
    /// - Parameter blendMode: The requested compositing operation.
    /// - Returns: The separate RGB and alpha blend factors for the operation.
    static func configuration(for blendMode: CGBlendMode) -> GLBlendConfiguration {
        switch blendMode {
        case .normal:
            .normal()
        case .screen:
            GLBlendConfiguration(
                sourceRGB: .oneMinusDestinationColor,
                destinationRGB: .one,
                sourceAlpha: .one,
                destinationAlpha: .oneMinusSourceAlpha
            )
        case .clear:
            GLBlendConfiguration(
                sourceRGB: .zero,
                destinationRGB: .zero,
                sourceAlpha: .zero,
                destinationAlpha: .zero
            )
        case .copy:
            GLBlendConfiguration(
                sourceRGB: .one,
                destinationRGB: .zero,
                sourceAlpha: .one,
                destinationAlpha: .zero
            )
        case .sourceIn:
            GLBlendConfiguration(
                sourceRGB: .destinationAlpha,
                destinationRGB: .zero,
                sourceAlpha: .destinationAlpha,
                destinationAlpha: .zero
            )
        case .sourceOut:
            GLBlendConfiguration(
                sourceRGB: .oneMinusDestinationAlpha,
                destinationRGB: .zero,
                sourceAlpha: .oneMinusDestinationAlpha,
                destinationAlpha: .zero
            )
        case .sourceAtop:
            GLBlendConfiguration(
                sourceRGB: .destinationAlpha,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .destinationAlpha,
                destinationAlpha: .oneMinusSourceAlpha
            )
        case .destinationOver:
            GLBlendConfiguration(
                sourceRGB: .oneMinusDestinationAlpha,
                destinationRGB: .one,
                sourceAlpha: .oneMinusDestinationAlpha,
                destinationAlpha: .one
            )
        case .destinationIn:
            GLBlendConfiguration(
                sourceRGB: .zero,
                destinationRGB: .sourceAlpha,
                sourceAlpha: .zero,
                destinationAlpha: .sourceAlpha
            )
        case .destinationOut:
            GLBlendConfiguration(
                sourceRGB: .zero,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .zero,
                destinationAlpha: .oneMinusSourceAlpha
            )
        case .destinationAtop:
            GLBlendConfiguration(
                sourceRGB: .oneMinusDestinationAlpha,
                destinationRGB: .sourceAlpha,
                sourceAlpha: .oneMinusDestinationAlpha,
                destinationAlpha: .sourceAlpha
            )
        case .xor:
            GLBlendConfiguration(
                sourceRGB: .oneMinusDestinationAlpha,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .oneMinusDestinationAlpha,
                destinationAlpha: .oneMinusSourceAlpha
            )
        case .plusLighter:
            GLBlendConfiguration(
                sourceRGB: .one,
                destinationRGB: .one,
                sourceAlpha: .one,
                destinationAlpha: .one
            )
        case .multiply, .overlay, .darken, .lighten, .colorDodge, .colorBurn,
             .softLight, .hardLight, .difference, .exclusion, .hue, .saturation,
             .color, .luminosity, .plusDarker:
            .normal(fallsBackToNormal: true)
        }
    }
}
