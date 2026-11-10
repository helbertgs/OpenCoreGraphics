import Foundation

/// A device-space region that restricts subsequent drawing.
enum CGClipRegion: Equatable, Sendable {
    /// An axis-aligned rectangle that can be represented by an OpenGL scissor.
    case rectangle(CGRect)

    /// A path whose interior is represented by a stencil mask.
    case path(CGPath, rule: CGPath.CGPathFillRule)

    /// The smallest device-space rectangle enclosing this region.
    var boundingBox: CGRect {
        switch self {
        case let .rectangle(rect):
            rect
        case let .path(path, _):
            path.boundingBoxOfPath
        }
    }

    /// Converts the region into the backend command used to apply it.
    var drawCommand: DrawCommand {
        switch self {
        case let .rectangle(rect):
            .clipRect(rect)
        case let .path(path, rule):
            .clip(path: path, rule: rule)
        }
    }
}

/// The color, offset, and blur radius captured for a path shadow.
struct CGShadow: Equatable, Sendable {
    /// The displacement from the source shape in device-space pixels.
    let offset: CGSize

    /// The Gaussian standard deviation in device-space pixels.
    let blur: Double

    /// The color composited beneath the source shape.
    let color: CGColor

    /// Creates a shadow with device-space rendering parameters.
    /// - Parameters:
    ///   - offset: The displacement from the source shape.
    ///   - blur: The Gaussian standard deviation.
    ///   - color: The shadow color and opacity.
    init(offset: CGSize, blur: Double, color: CGColor) {
        self.offset = offset
        self.blur = blur
        self.color = color
    }
}

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

    /// The limit on the length of a miter join, relative to half the line width.
    var miterLimit: Double = 10

    /// The repeating lengths of painted and unpainted portions of stroked lines.
    var lineDash: [Double] = []

    /// The offset into the line dash pattern at the beginning of a subpath.
    var lineDashPhase: Double = 0

    /// The compositing operation used when drawing.
    var blendMode: CGBlendMode = .normal

    /// The shadow applied to subsequent path drawing, or nil when disabled.
    var shadow: CGShadow?

    /// The quality hint used when interpolating images.
    var interpolationQuality: CGInterpolationQuality = .default

    /// The method used to map colors to the destination color space.
    var renderingIntent: CGColorRenderingIntent = .defaultIntent

    /// The clipping coverage mask, or nil when no clipping has been applied.
    var clip: CoverageMask?

    /// The ordered device-space regions that define the current clip.
    var clipRegions: [CGClipRegion] = []

    /// The selected font's name, or nil when no font has been selected.
    var font: String?

    /// The size used to draw text, in text space units.
    var fontSize: Double = 12

    /// The additional spacing between adjacent characters.
    var characterSpacing: Double = 0

    /// The operation used to draw text.
    var textDrawingMode: CGTextDrawingMode = .fill
}
