import Foundation

/// A backend-independent drawing operation with all rendering state captured.
enum DrawCommand: Equatable, Sendable {
    /// Fills a path using the selected interior rule and compositing mode.
    case fillPath(path: CGPath, rule: CGPath.CGPathFillRule, color: CGColor, blendMode: CGBlendMode)

    /// Strokes a path using the selected line style and compositing mode.
    case strokePath(path: CGPath, color: CGColor, style: StrokeStyle, blendMode: CGBlendMode)

    /// Draws image bytes into a destination rectangle.
    case drawImage(data: Data?, width: Int, height: Int, destination: CGRect, blendMode: CGBlendMode)

    /// Restricts subsequent drawing to the interior of a path.
    case clip(path: CGPath, rule: CGPath.CGPathFillRule)

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

    /// The maximum ratio between a miter length and the line width.
    let miterLimit: Double

    /// The alternating painted and unpainted lengths of a dashed line.
    let dash: [Double]
}
