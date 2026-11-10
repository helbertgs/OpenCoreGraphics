import Foundation

/// A backend-independent drawing operation with all rendering state captured.
enum DrawCommand: Equatable, Sendable {
    /// Fills a path using the selected interior rule and compositing mode.
    case fillPath(
        path: CGPath,
        rule: CGPath.CGPathFillRule,
        color: CGColor,
        blendMode: CGBlendMode,
        shadow: CGShadow? = nil
    )

    /// Strokes a path using the selected line style and compositing mode.
    case strokePath(
        path: CGPath,
        color: CGColor,
        style: StrokeStyle,
        blendMode: CGBlendMode,
        shadow: CGShadow? = nil
    )

    /// Draws an image into transformed destination corners.
    case drawImage(
        image: CGImageSnapshot,
        destination: [CGPoint],
        interpolationQuality: CGInterpolationQuality,
        byTiling: Bool,
        blendMode: CGBlendMode
    )

    /// Restricts subsequent drawing to the interior of a path.
    case clip(path: CGPath, rule: CGPath.CGPathFillRule)

    /// Restricts subsequent drawing to an axis-aligned device-space rectangle.
    case clipRect(CGRect)

    /// Removes all clipping restrictions from subsequent drawing.
    case resetClip

    /// Draws positioned glyphs using a font snapshot and captured text state.
    case glyphs(glyphs: [CGGlyph], positions: [CGPoint], fontName: String?, fontSize: Double, color: CGColor, blendMode: CGBlendMode)
}

/// The line parameters captured by a stroke drawing command.
struct StrokeStyle: Equatable, Sendable {
    /// The line width in device-space pixels.
    let width: Double

    /// The shape used to draw open line endpoints.
    let cap: CGLineCap

    /// The shape used to draw connected line segments.
    let join: CGLineJoin

    /// The maximum ratio between a miter length and half the line width.
    let miterLimit: Double

    /// The alternating painted and unpainted lengths of a dashed line.
    let dash: [Double]

    /// The offset into the dash pattern at the beginning of each subpath.
    let dashPhase: Double

    /// The alternating painted and unpainted lengths of a dashed line.
    var dashLengths: [Double] {
        dash
    }

    /// Creates a line style with an optional dash pattern and phase.
    /// - Parameters:
    ///   - width: The line width in device-space pixels.
    ///   - cap: The shape used to draw open line endpoints.
    ///   - join: The shape used to draw connected line segments.
    ///   - miterLimit: The maximum ratio between a miter length and half the line width.
    ///   - dashPhase: The offset into the dash pattern at the beginning of each subpath.
    ///   - dashLengths: The alternating painted and unpainted lengths.
    init(
        width: Double,
        cap: CGLineCap,
        join: CGLineJoin,
        miterLimit: Double,
        dashPhase: Double = 0,
        dashLengths: [Double] = []
    ) {
        self.width = width
        self.cap = cap
        self.join = join
        self.miterLimit = miterLimit
        dash = dashLengths
        self.dashPhase = dashPhase
    }

    /// Creates a line style using the legacy dash argument label.
    /// - Parameters:
    ///   - width: The line width in device-space pixels.
    ///   - cap: The shape used to draw open line endpoints.
    ///   - join: The shape used to draw connected line segments.
    ///   - miterLimit: The maximum ratio between a miter length and half the line width.
    ///   - dash: The alternating painted and unpainted lengths.
    init(width: Double, cap: CGLineCap, join: CGLineJoin, miterLimit: Double, dash: [Double]) {
        self.init(width: width, cap: cap, join: join, miterLimit: miterLimit, dashLengths: dash)
    }
}
