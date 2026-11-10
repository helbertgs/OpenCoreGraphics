import Foundation

/// A value snapshot of the drawing parameters stored by a graphics context.
struct CGGraphicsState: Sendable {
    /// The transform from user space to device space.
    var ctm: CGAffineTransform = .identity

    /// The color used to fill paths.
    var fillColor: CGColor = .black

    /// The color used to stroke paths.
    var strokeColor: CGColor = .black

    /// The color space used to interpret the fill color.
    var fillColorSpace: CGColorSpace = .genericRGBLinear

    /// The color space used to interpret the stroke color.
    var strokeColorSpace: CGColorSpace = .genericRGBLinear

    /// The width of stroked lines, in user space units.
    var lineWidth: Double = 1

    /// The style used to draw the endpoints of stroked lines.
    var lineCap: CGLineCap = .butt

    /// The style used to draw the junctions between stroked line segments.
    var lineJoin: CGLineJoin = .miter

    /// The limit on the length of a miter join, relative to the line width.
    var miterLimit: Double = 10

    /// The repeating lengths of painted and unpainted portions of stroked lines.
    var lineDash: [Double] = []

    /// The compositing operation used when drawing.
    var blendMode: CGBlendMode = .normal

    /// The quality hint used when interpolating images.
    var interpolationQuality: CGInterpolationQuality = .default

    /// The method used to map colors to the destination color space.
    var renderingIntent: CGColorRenderingIntent = .defaultIntent

    /// The clipping path, or nil when no path has been applied.
    var clip: CGPath?

    /// The selected font's name, or nil when no font has been selected.
    var font: String?

    /// The size used to draw text, in text space units.
    var fontSize: Double = 12

    /// The additional spacing between adjacent characters.
    var characterSpacing: Double = 0

    /// The operation used to draw text.
    var textDrawingMode: CGTextDrawingMode = .fill
}
