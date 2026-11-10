import Foundation

/// A Core Graphics 2D drawing environment.
/// 
/// A CGContext instance represents a Core Graphics drawing destination. 
/// A graphics context contains drawing parameters and all device-specific information needed to render the paint on a page to the destination, whether the destination is a window in an application, a bitmap image, a PDF document, or a printer.
open class CGContext {

    // MARK: - Creating Bitmap Graphics Contexts

    /// Creates a bitmap graphics context.
    /// 
    /// When you draw into this context, Core Graphics renders your drawing as bitmapped data in the specified block of memory.
    /// The pixel format for a new bitmap context is determined by three parameters—the number of bits per component, the color space, and an alpha option (expressed as a ``CGBitmapInfo`` constant). 
    /// The alpha value determines the opacity of a pixel when it is drawn.
    /// - Parameters:
    ///   - data: A pointer to the destination in memory where the drawing is to be rendered. 
    ///           The size of this memory block should be at least (bytesPerRow*height) bytes.
    ///           Pass nil if you want this function to allocate memory for the bitmap. 
    ///           This frees you from managing your own memory, which reduces memory leak issues.
    ///   - width: The width, in pixels, of the required bitmap.
    ///   - height: The height, in pixels, of the required bitmap
    ///   - bitsPerComponent: The number of bits to use for each component of a pixel in memory. 
    ///                       For example, for a 32-bit pixel format and an RGB color space, you would specify a value of 8 bits per component. 
    ///                       For the list of supported pixel formats, see “Supported Pixel Formats” in the Graphics Contexts
    ///   - bytesPerRow: The number of bytes of memory to use per row of the bitmap. 
    ///                  If the data parameter is ``nil``, passing a value of 0 causes the value to be calculated automatically.
    ///   - space: The color space to use for the bitmap context. 
    ///            Note that indexed color spaces are not supported for bitmap graphics contexts.
    ///   - bitmapInfo: Constants that specify whether the bitmap should contain an alpha channel, the alpha channel’s relative location in a pixel, and information about whether the pixel components are floating-point or integer values. 
    ///                 The constants for specifying the alpha channel information are declared with the ``CGImageAlphaInfo`` type but can be passed to this parameter safely. 
    ///                 You can also pass the other constants associated with the ``CGBitmapInfo`` type.
    public init(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace, bitmapInfo: Int) {
        self.data = Data()
        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        self.bytesPerRow = bytesPerRow
        self.colorSpace = space
        self.bitmapInfo = CGBitmapInfo(rawValue: bitmapInfo)
        self.alphaInfo = .premultipliedLast
        self.bitsPerPixel = 0
    }

    /// Compatibility name for contexts previously created by `CGWindow`.
    @available(*, deprecated, message: "Use CGContext instead.")
    public typealias CGWindowContext = CGContext

    /// Creates a graphics context with the specified pixel dimensions.
    /// - Parameters:
    ///   - width: The width of the drawing destination in pixels.
    ///   - height: The height of the drawing destination in pixels.
    public convenience init(width: Int, height: Int) {
        self.init(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: .genericRGBLinear,
            bitmapInfo: 0
        )
    }

    /// Returns an affine transform that maps user space coordinates to device space coordinates.
    open var userSpaceToDeviceSpaceTransform: CGAffineTransform {
        ctm
    }

    /// Returns the inverse affine transform used for device-to-user conversions.
    private var deviceSpaceToUserSpaceTransform: CGAffineTransform {
        let transform = userSpaceToDeviceSpaceTransform
        let determinant = transform.m11 * transform.m22 - transform.m21 * transform.m12
        guard determinant != 0 else { return .identity }

        var inverse = CGAffineTransform.identity
        inverse.m11 = transform.m22 / determinant
        inverse.m12 = -transform.m12 / determinant
        inverse.m21 = -transform.m21 / determinant
        inverse.m22 = transform.m11 / determinant
        inverse.m41 = (transform.m21 * transform.m42 - transform.m22 * transform.m41) / determinant
        inverse.m42 = (transform.m12 * transform.m41 - transform.m11 * transform.m42) / determinant
        return inverse
    }

    /// Returns a point that is transformed from user space coordinates to device space coordinates.
    /// - Parameter point: The point, in user space coordinates, to transform.
    /// - Returns: The coordinates of the point in device space coordinates.
    public func convertToDeviceSpace(_ point: CGPoint) -> CGPoint {
        point.applying(userSpaceToDeviceSpaceTransform)
    }

    /// Returns a point that is transformed from device space coordinates to user space coordinates.
    /// - Parameter point: The point, in device space coordinates, to transform.
    /// - Returns: The coordinates of the point in user space coordinates.
    open func convertToUserSpace(_ point: CGPoint) -> CGPoint {
        point.applying(deviceSpaceToUserSpaceTransform)
    }

    /// Returns a rectangle that is transformed from user space coordinate to device space coordinates.
    /// 
    /// In general affine transforms do not preserve rectangles. 
    /// As a result, this function returns the smallest rectangle that contains the transformed corner points of the rectangle.
    /// - Parameter rect: The rectangle, in user space coordinates, to transform.
    /// - Returns: The rectangle in device space coordinates.
    open func convertToDeviceSpace(_ rect: CGRect) -> CGRect {
        let transform = userSpaceToDeviceSpaceTransform
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ].map { $0.applying(transform) }
        let first = corners[0]
        let bounds = corners.dropFirst().reduce(CGRect(x: first.x, y: first.y, width: 0, height: 0)) { rect, point in
            let minX = min(rect.minX, point.x)
            let minY = min(rect.minY, point.y)
            let maxX = max(rect.maxX, point.x)
            let maxY = max(rect.maxY, point.y)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return bounds
    }

    /// Returns a rectangle that is transformed from device space coordinate to user space coordinates.
    /// 
    /// In general, affine transforms do not preserve rectangles. 
    /// As a result, this function returns the smallest rectangle that contains the transformed corner points of the rectangle.
    /// - Parameter rect: The rectangle, in device space coordinates, to transform.
    /// - Returns: The rectangle in user space coordinates.
    open func convertToUserSpace(_ rect: CGRect) -> CGRect {
        let transform = deviceSpaceToUserSpaceTransform
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ].map { $0.applying(transform) }
        let first = corners[0]
        return corners.dropFirst().reduce(CGRect(x: first.x, y: first.y, width: 0, height: 0)) { rect, point in
            let minX = min(rect.minX, point.x)
            let minY = min(rect.minY, point.y)
            let maxX = max(rect.maxX, point.x)
            let maxY = max(rect.maxY, point.y)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    /// Returns a size that is transformed from user space coordinates to device space coordinates.
    /// - Parameter size: The size, in user space coordinates, to transform.
    /// - Returns: The size in device space coordinates.
    open func convertToDeviceSpace(_ size: CGSize) -> CGSize {
        size.applying(userSpaceToDeviceSpaceTransform)
    }

    /// Returns a size that is transformed from device space coordinates to user space coordinates.
    /// - Parameter size: The size, in device space coordinates, to transform.
    /// - Returns: The size in user space coordinates.
    open func convertToUserSpace(_ size: CGSize) -> CGSize {
        size.applying(deviceSpaceToUserSpaceTransform)
    }

    // MARK: - Constructing a Current Graphics Path

    /// Returns a path object built from the current path information in a graphics context.
    public var path: CGPath?

    /// The render target that receives queued drawing commands.
    var renderTarget: CGRenderTarget?

    /// Drawing commands waiting to be submitted to the render target.
    private var pendingDrawCommands: [DrawCommand] = []

    /// The stack of saved graphics-state snapshots.
    private var graphicsStateStack: [CGGraphicsState] = []

    /// The current clipping path captured by graphics-state snapshots.
    private var clip: CGPath?

    /// The current line cap style captured by graphics-state snapshots.
    private var lineCap: CGLineCap = .butt

    /// The current line join style captured by graphics-state snapshots.
    private var lineJoin: CGLineJoin = .miter

    /// The current miter limit captured by graphics-state snapshots.
    private var miterLimit: Double = 10

    /// The current line dash pattern captured by graphics-state snapshots.
    private var lineDash: [Double] = []

    /// Creates a new empty path in a graphics context.
    /// 
    /// A graphics context can have only a single path in use at any time. 
    /// If the specified context already contains a current path when you call this function, the old path and any data associated with it is discarded.
    /// 
    /// The current path is not part of the graphics state. 
    /// Consequently, saving and restoring the graphics state has no effect on the current path.
    public func beginPath() {
        path = CGPath()
    }

    /// Begins a new subpath at the specified point.
    /// 
    /// The specified point becomes the start point of a new subpath. 
    /// The current point is set to this start point.
    /// - Parameter point: The point, in user space coordinates, at which to start a new subpath.
    public func move(to point: CGPoint) {
        path?.move(to: point, transform: ctm)
    }

    /// Appends a straight line segment from the current point to the specified point.
    /// 
    /// After adding the line segment, the current point is set to the endpoint of the line segment.
    /// - Parameter point: The location, in user space coordinates, for the end of the new line segment.
    public func addLine(to point: CGPoint) {
        path?.addLine(to: point, transform: ctm)
    }

    /// Adds a sequence of connected straight-line segments to the current path.
    /// 
    /// Calling this convenience method is equivalent to calling the ``move(to:)`` method with the first value in the points array, then calling the ``addLine(to:)`` method for each subsequent point until the array is exhausted. 
    /// After calling this method, the path’s current point is the last point in the array.
    /// - Parameter points: An array of values that specify the start and end points of the line segments to draw. 
    ///                     Each point in the array specifies a position in user space. 
    ///                     The first point in the array specifies the initial starting point.
    public func addLines(between points: [CGPoint]) {
        path?.addLines(between: points, transform: ctm)
    }

    /// Adds a rectangular path to the current path.
    /// 
    /// This is a convenience function that adds a rectangle to a path, starting by moving to the bottom left corner and then adding lines counter-clockwise to create a rectangle, closing the subpath.
    /// - Parameter rect: A rectangle, specified in user space coordinates.
    public func addRect(_ rect: CGRect) {
        path?.addRect(rect, transform: ctm)
    }

    /// Adds a set of rectangular paths to the current path.
    /// 
    /// Calling this convenience method is equivalent to repeatedly calling the ``addRect(_:)`` method for each rectangle in the array.
    /// - Parameter rects: An array of rectangles, specified in user space coordinates.
    public func addRects(_ rects: [CGRect]) {
        path?.addRects(rects, transform: ctm)
    }

    /// Adds an ellipse that fits inside the specified rectangle.
    /// 
    /// The ellipse is approximated by a sequence of Bézier curves. Its center is the midpoint of the rectangle defined by the rect parameter. 
    /// If the rectangle is square, then the ellipse is circular with a radius equal to one-half the width (or height) of the rectangle. 
    /// If the rect parameter specifies a rectangular shape, then the major and minor axes of the ellipse are defined by the width and height of the rectangle.
    /// 
    /// The ellipse forms a complete subpath of the path—that is, the ellipse drawing starts with a move-to operation and ends with a close-subpath operation, with all moves oriented in the clockwise direction.
    /// - Parameter rect: A rectangle that defines the area for the ellipse to fit in.
    public func addEllipse(in rect: CGRect) {
        path?.addEllipse(in: rect, transform: ctm)
    }

    /// Adds an arc of a circle to the current path, specified with a radius and angles.
    /// 
    /// This method calculates starting and ending points using the radius and angles you specify, uses a sequence of cubic Bézier curves to approximate a segment of a circle between those points, and then appends those curves to the current path.
    /// The clockwise parameter determines the direction in which the arc is created; the actual direction of the final path is dependent on the current transformation matrix of the graphics context.
    /// 
    /// If the current path already contains a subpath, this method adds a line connecting the current point to the starting point of the arc. 
    /// If the current path is empty, his method creates a new subpath whose starting point is the starting point of the arc. 
    /// The ending point of the arc becomes the new current point of the path.
    /// - Parameters:
    ///   - center: The center of the arc, in user space coordinates.
    ///   - radius: The radius of the arc, in user space coordinates.
    ///   - startAngle: The angle to the starting point of the arc, measured in radians from the positive x-axis.
    ///   - endAngle: The angle to the end point of the arc, measured in radians from the positive x-axis.
    ///   - clockwise: true to make a clockwise arc; false to make a counterclockwise arc.
    public func addArc(center: CGPoint, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool) {
        path?.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise, transform: ctm)
    }
    
    /// Adds an arc of a circle to the current path, specified with a radius and two tangent lines.
    /// 
    /// This method calculates two tangent lines—the first from the current point to the ``tangent1End`` point, and the second from the ``tangent1End`` point to the ``tangent2End`` point—then calculates the start and end points for a circular arc of the specified radius such that the arc is tangent to both lines. 
    /// Finally, this method approximates that arc with a sequence of cubic Bézier curves and appends those curves to the current path.
    /// 
    /// If the starting point of the arc (that is, the point where a circle of the specified radius must meet the first tangent line in order to also be tangent to the second line) is not the current point, this method appends a straight line segment from the current point to the starting point of the arc.
    /// The ending point of the arc (that is, the point where a circle of the specified radius must meet the second tangent line in order to also be tangent to the first line) becomes the new current point of the path.
    /// - Parameters:
    ///   - tangent1End: The end point, in user space coordinates, for the first tangent line to be used in constructing the arc. (The start point for this tangent line is the path’s current point.)
    ///   - tangent2End: The end point, in user space coordinates, for the second tangent line to be used in constructing the arc. (The start point for this tangent line is the tangent1End point.)
    ///   - radius: The radius of the arc, in user space coordinates.
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: Double) {
        guard let currentPath = path else { return }
        guard currentPath.isEmpty == false else {
            path?.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius, transform: ctm)
            return
        }

        var tangentArc = CGPath()
        tangentArc.move(to: convertToUserSpace(currentPath.currentPoint))
        tangentArc.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius)
        guard let transformedArc = tangentArc.copy(using: ctm) else { return }
        appendArcElements(transformedArc.subpath.dropFirst())
    }

    /// Appends transformed arc elements to the current path without adding a separate subpath.
    private func appendArcElements(_ elements: ArraySlice<CGPath.CGPathElement>) {
        for element in elements {
            switch element.type {
            case .addLineToPoint:
                guard let end = element.points.last else { continue }
                path?.addLine(to: end)
            case .addQuadCurveToPoint:
                guard element.points.count == 3 else { continue }
                path?.addQuadCurve(to: element.points[2], control: element.points[1])
            case .addCurveToPoint:
                guard element.points.count == 4 else { continue }
                path?.addCurve(
                    to: element.points[3],
                    control1: element.points[1],
                    control2: element.points[2]
                )
            case .none, .moveToPoint, .addRectToPoint, .closeSubpath:
                continue
            }
        }
    }

    /// Adds a cubic Bézier curve to the current path, with the specified end point and control points.
    /// 
    /// This method constructs a curve starting from the path’s current point and ending at the specified end point, with curvature defined by the two control points. 
    /// After this method appends that curve to the current path, the end point of the curve becomes the path’s current point.
    /// - Parameters:
    ///   - end: The point, in user space coordinates, at which to end the curve.
    ///   - control1: The first control point of the curve, in user space coordinates.
    ///   - control2: The second control point of the curve, in user space coordinates.
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        path?.addCurve(to: end, control1: control1, control2: control2, transform: ctm)
    }

    /// Adds a quadratic Bézier curve to the current path, with the specified end point and control point.
    /// 
    /// This method constructs a curve starting from the path’s current point and ending at the specified end point, with curvature defined by the control point. 
    /// After this method appends that curve to the current path, the end point of the curve becomes the path’s current point.
    /// - Parameters:
    ///   - end: The point, in user space coordinates, at which to end the curve.
    ///   - control: The control point of the curve, in user space coordinates.
    public func addQuadCurve(to end: CGPoint, control: CGPoint) {
        path?.addQuadCurve(to: end, control: control, transform: ctm)
    }

    /// Adds a previously created path object to the current path in a graphics context.
    /// 
    /// If the source path is non-empty, then its path elements are appended in order onto the current path. 
    /// The current transformation matrix (CTM) is applied to the points before adding them to the path.
    /// 
    /// After the call completes, the start point and current point of the path are those of the last subpath in path.
    /// - Parameter path: A previously created path object.
    public func addPath(_ path: CGPath) {
        self.path?.addPath(path, transform: ctm)
    }

    /// Closes and terminates the current path’s subpath.
    /// 
    /// Appends a line from the current point to the starting point of the current subpath and ends the subpath.
    /// After closing the subpath, your application can begin a new subpath without first calling ``move(to:)``. 
    /// In this case, a new subpath is implicitly created with a starting and current point equal to the previous subpath’s starting point.
    /// 
    /// If the current path is empty or the current subpath is already closed, this function does nothing.
    public func closePath() {
        path?.closeSubpath()
    }

    // MARK: - Examining the Current Graphics Path

    /// Returns the smallest rectangle that contains the current path.
    /// 
    /// The bounding box is the smallest rectangle completely enclosing all points in a path, including control points for Bézier cubic and quadratic curves.
    public var boundingBoxOfPath: CGRect {
        path?.boundingBox ?? .zero
    }

    /// Returns the current point in a non-empty path.
    public var currentPointOfPath: CGPoint {
        path?.currentPoint ?? .zero
    }

    /// Indicates whether the current path contains any subpaths.
    public var isPathEmpty: Bool {
        path?.isEmpty ?? true
    }

    /// Checks to see whether the specified point is contained in the current path.
    /// 
    /// A point is contained within the path of a graphics context if the point is inside the painted region when the path is stroked or filled with opaque colors using the specified path drawing mode. 
    /// A point can be inside a path only if the path is explicitly closed by calling the function ``closePath()`` for paths drawn directly to the current context, or ``closeSubpath()`` for paths first created as ``CGPath`` objects and then drawn to the current context.
    /// - Parameters:
    ///   - point: The point to check, specified in user space units.
    ///   - mode: A path drawing mode. See CGPathDrawingMode.
    /// - Returns: Returns true if point is inside the current path of the graphics context; false otherwise.
    public func pathContains(_ point: CGPoint, mode: CGPath.CGPathDrawingMode) -> Bool {
        guard let path = path else { return false }
        return path.contains(point)
    }

    // MARK: - Drawing the Current Graphics Path

    /// Draws the current path using the provided drawing mode.
    /// 
    /// The current path is cleared as a side effect of calling this function.
    /// - Parameter mode: A path drawing mode constant—``.fill``, ``.eoFill``, ``.stroke``, ``.fillStroke``, or ``.eoFillStroke``.
    open func drawPath(using mode: CGPath.CGPathDrawingMode) {
        guard let path else { return }

        switch mode {
        case .fill:
            pendingDrawCommands.append(.fillPath(path: path, rule: .winding, color: fillColor, blendMode: blendMode))
        case .eoFill:
            pendingDrawCommands.append(.fillPath(path: path, rule: .evenOdd, color: fillColor, blendMode: blendMode))
        case .stroke:
            pendingDrawCommands.append(.strokePath(path: path, color: strokeColor, style: currentStrokeStyle, blendMode: blendMode))
        case .fillStroke:
            pendingDrawCommands.append(.fillPath(path: path, rule: .winding, color: fillColor, blendMode: blendMode))
            pendingDrawCommands.append(.strokePath(path: path, color: strokeColor, style: currentStrokeStyle, blendMode: blendMode))
        case .eoFillStroke:
            pendingDrawCommands.append(.fillPath(path: path, rule: .evenOdd, color: fillColor, blendMode: blendMode))
            pendingDrawCommands.append(.strokePath(path: path, color: strokeColor, style: currentStrokeStyle, blendMode: blendMode))
        }

        self.path = nil
    }

    /// Paints the area within the current path, as determined by the specified fill rule.
    /// 
    /// If the current path contains any non-closed subpaths, this method treats each subpath as if it had been closed with the ``closePath()`` method, then applies the specified rule to determine which areas to fill.
    /// After filling the path, this method clears the context’s current path.
    /// - Parameter rule: The rule for determining which areas to treat as the interior of the path.
    open func fillPath(using rule: CGPath.CGPathFillRule = .winding) {
        guard let path = self.path else { return }
        pendingDrawCommands.append(.fillPath(path: path, rule: rule, color: fillColor, blendMode: blendMode))
        self.path = nil
    }

    /// Paints a line along the current path.
    /// 
    /// The line width and stroke color of the context’s graphics state are used to paint the path. 
    /// The current path is cleared as a side effect of calling this function.
    open func strokePath() {
        guard let path = self.path else { return }
        pendingDrawCommands.append(.strokePath(path: path, color: strokeColor, style: currentStrokeStyle, blendMode: blendMode))
        self.path = nil
    }

    /// Captures the current line parameters for a stroke command.
    private var currentStrokeStyle: StrokeStyle {
        StrokeStyle(width: lineWidth, cap: lineCap, join: lineJoin, miterLimit: miterLimit, dashLengths: lineDash)
    }

    // MARK: - Drawing Shapes

    /// Paints a transparent rectangle.
    /// 
    /// If the provided context is a window or bitmap context, Core Graphics clears the rectangle. 
    /// For other context types, Core Graphics fills the rectangle in a device-dependent manner. 
    /// However, you should not use this function in contexts other than window or bitmap contexts.
    /// - Parameter rect: The rectangle, in user space coordinates.
    open func clear(_ rect: CGRect) {
        let clearPath = CGPath(rect: rect, transform: ctm)
        pendingDrawCommands.append(.fillPath(path: clearPath, rule: .winding, color: .clear, blendMode: .clear))
        path = nil
    }

    /// Paints the area contained within the provided rectangle, using the fill color in the current graphics state.
    /// 
    /// The current path is cleared as a side effect of calling this function.
    /// - Parameter rect: A rectangle, in user space coordinates.
    open func fill(_ rect: CGRect) {
        path = .init(rect: rect, transform: ctm)
        drawPath(using: .fill)
        path = nil
    }

    /// Paints the areas contained within the provided rectangles, using the fill color in the current graphics state.
    /// 
    /// The current path is cleared as a side effect of calling this function.
    /// - Parameter rects: An array of rectangles, in user space coordinates.
    open func fill(_ rects: [CGRect]) {
        rects.forEach {
            fill($0)
        }
    }

    /// Paints the area of the ellipse that fits inside the provided rectangle, using the fill color in the current graphics state.
    /// 
    /// The current path is cleared as a side effect of calling this function.
    /// - Parameter rect: A rectangle that defines the area for the ellipse to fit in.
    open func fillEllipse(in rect: CGRect) {
        path = .init(ellipseIn: rect, transform: ctm)
        drawPath(using: .fill)
        path = nil
    }

    /// Paints a rectangular path.
    /// 
    /// The line width and stroke color of the context’s graphics state are used to paint the path. 
    /// The current path is cleared as a side effect of calling this function.
    /// - Parameter rect: A rectangle, specified in user space coordinates.
    open func stroke(_ rect: CGRect) {
        path = .init(rect: rect, transform: ctm)
        drawPath(using: .stroke)
        path = nil
    }

    /// Strokes an ellipse that fits inside the specified rectangle.
    /// 
    /// The current path is cleared as a side effect of calling this function.
    /// - Parameter rect: A rectangle that defines the area for the ellipse to fit in.
    open func strokeEllipse(in rect: CGRect) {
        path = .init(ellipseIn: rect, transform: ctm)
        drawPath(using: .stroke)
        path = nil
    }

    /// Strokes a sequence of line segments.
    /// 
    /// This function creates a new path, adds the individual line segments to the path, and then strokes the path. 
    /// The current path is cleared as a side effect of calling this function.
    /// - Parameter points: An array of points, organized as pairs—the starting point of a line segment followed by the ending point of a line segment. 
    ///                     For example, the first point in the array specifies the starting position of the first line, the second point specifies the ending position of the first line, the third point specifies the starting position of the second line, and so forth.
    public func strokeLineSegments(between points: [CGPoint]) {
    }

    // MARK: - Drawing Images

    /// Draws an image in the specified area.
    /// 
    /// This method scales the image (disproportionately, if necessary) to fit the bounds specified by the rect parameter.
    /// When the byTiling parameter is true, the image is tiled in user space—thus, unlike when drawing with patterns, the current transformation (see the ctm property) affects the final result.
    /// - Parameters:
    ///   - image: The image to draw.
    ///   - rect: The rectangle, in user space coordinates, in which to draw the image.
    ///   - byTiling: If true, this method fills the context’s entire clipping region by tiling many copies of the image, and the rect parameter defines the origin and size of the tiling pattern.
    ///               If false (the default), this method draws a single copy of the image in the area defined by the rect parameter.
    open func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) {
        pendingDrawCommands.append(
            .drawImage(
                data: image.dataProvider?.data,
                width: image.width,
                height: image.height,
                destination: convertToDeviceSpace(rect),
                blendMode: blendMode
            )
        )
    }

    /// Returns the current level of interpolation quality for a graphics context.
    /// 
    /// Interpolation quality is a graphics state parameter that provides a hint for the level of quality to use for image interpolation (for example, when scaling the image). 
    /// Not all contexts support all interpolation quality levels.
    public var interpolationQuality: CGInterpolationQuality = .default

    // MARK: - Drawing Text

    private var font: CGFont?

    private var fontSize: Double = 16

    private var characterSpacing: Double = 2

    private var textDrawingMode: CGTextDrawingMode = .fill

    /// Returns the current text matrix.
    public var textMatrix: CGAffineTransform = .identity

    /// Returns a point that specifies the x and y values at which text is to be drawn, in user space coordinates.
    public var textPosition: CGPoint = .zero

    /// Sets the current character spacing.
    /// 
    /// Core Graphics adds the additional space to the advance between the origin of one character and the origin of the next character.
    /// - Parameter spacing: A value that represents the amount of additional space to place between glyphs, in text space coordinates.
    public func setCharacterSpacing(_ spacing: Double) {
        self.characterSpacing = spacing
    }

    /// Sets the platform font in a graphics context.
    /// - Parameter font: A font.
    public func setFont(_ font: CGFont) {        
        self.font = font
    }

    /// Sets the current font size.
    /// - Parameter size: A font size, expressed in text space units.
    public func setFontSize(_ size: Double) {
        self.fontSize = size
    }

    /// Sets the current text drawing mode.
    /// - Parameter mode: A text drawing mode (such as ``.fill`` or ``.stroke``) that specifies how Core Graphics renders individual glyphs in a graphics context.
    public func setTextDrawingMode(_ mode: CGTextDrawingMode) {
        self.textDrawingMode = mode
    }

    /// Draws a set of glyphs at a set of corresponding positions.
    /// 
    /// Points in the positions array are specified in text space, so the ``textMatrix`` property defines their transformation to user space.
    /// - Parameters:
    ///   - glyphs: An array of glyphs.
    ///   - positions: An array positions for the glyphs. Each item in this array specifies the position at which to draw the glyph at the corresponding index in the glyphs array.
    public func showGlyphs(_ glyphs: [CGGlyph], at positions: [CGPoint]) {
    }

    // MARK: - Setting Fill, Stroke, and Shadow Colors

    /// The current fill color in a graphics context.
    private var fillColor: CGColor = .clear

    /// The current fill color space in a graphics context.
    private var fillColorSpace: CGColorSpace = .genericRGBLinear

    /// The current stroke color in a graphics context.
    private var strokeColor: CGColor = .clear

    /// The current stroke color space in a graphics context.
    private var strokeColorSpace: CGColorSpace = .genericRGBLinear

    /// The current  line width for a graphics context.
    private var lineWidth: Double = 1.0

    /// Sets the current fill color in a graphics context, using a CGColor.
    /// - Parameter color: The new fill color.
    public func setFillColor(_ color: CGColor) {
        self.fillColor = color
    }

    /// Sets the current fill color to a value in the DeviceCMYK color space.
    /// 
    /// Core Graphics provides convenience functions for each of the device color spaces that allow you to set the fill or stroke color space and the fill or stroke color with one function call.
    /// When you call this function, two things happen:
    ///     - Core Graphics sets the current fill color space to DeviceCMYK.
    ///     - Core Graphics sets the current fill color to the value specified by the cyan, magenta, yellow, black, and alpha parameters.
    /// - Parameters:
    ///   - cyan: The cyan intensity value for the color to set. 
    ///   - magenta: The magenta intensity value for the color to set.
    ///   - yellow: The yellow intensity value for the color to set.
    ///   - black: The black intensity value for the color to set.
    ///   - alpha: A value that specifies the opacity level.
    public func setFillColor(cyan: Double, magenta: Double, yellow: Double, black: Double, alpha: Double) {
        self.fillColorSpace = .genericCMYK
        self.fillColor = .init(cyan: cyan, magenta: magenta, yellow: yellow, black: black, alpha: alpha)
    }

    /// Sets the current fill color to a value in the DeviceGray color space.
    /// 
    /// When you call this function, two things happen:
    ///   - Core Graphics sets the current fill color space to DeviceGray.
    ///   - Core Graphics sets the current fill color to the value you specify in the gray and alpha parameters.
    /// - Parameters:
    ///   - gray: A value that specifies the desired gray level. 
    ///   - alpha: A value that specifies the opacity level.
    public func setFillColor(gray: Double, alpha: Double) {
        self.fillColorSpace = .linearGray
        self.fillColor = .init(gray: gray, alpha: alpha)
    }

    /// Sets the current fill color to a value in the DeviceRGB color space.
    /// 
    /// When you call this function, two things happen:
    ///   - Core Graphics sets the current fill color space to DeviceRGB.
    ///   - Core Graphics sets the current fill color to the value specified by the red, green, blue, and alpha parameters.
    /// - Parameters:
    ///   - red: The red intensity value for the color to set.
    ///   - green: The green intensity value for the color to set.
    ///   - blue: The blue intensity value for the color to set.
    ///   - alpha: A value that specifies the opacity level.
    public func setFillColor(red: Double, green: Double, blue: Double, alpha: Double) {
        self.fillColorSpace = .genericRGBLinear
        self.fillColor = .init(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Sets the fill color space in a graphics context.
    /// 
    /// As a side effect of this function, Core Graphics assigns an appropriate initial value to the fill color, based on the specified color space.
    /// To change this value, call ``setFillColor(_:)``. 
    /// Note that the preferred API to use is now ``setFillColor(_:)``.
    /// - Parameter space: The new fill color space.
    public func setFillColorSpace(_ space: CGColorSpace) {
        self.fillColorSpace = space
    }

    /// Sets the current stroke color in a context, using a CGColor.
    /// - Parameter color: The new stroke color.
    public func setStrokeColor(_ color: CGColor) {
        self.strokeColor = color
    }

    /// Sets the current stroke color to a value in the DeviceCMYK color space.
    /// 
    /// When you call this function, two things happen:
    ///   - Core Graphics sets the current stroke color space to DeviceCMYK.
    ///   - Core Graphics sets the current stroke color to the value specified by the cyan, magenta, yellow, black, and alpha parameters.
    /// - Parameters:
    ///   - cyan: The cyan intensity value for the color to set.
    ///   - magenta: The magenta intensity value for the color to set.
    ///   - yellow: The yellow intensity value for the color to set. 
    ///   - black: The black intensity value for the color to set. 
    ///   - alpha: A value that specifies the opacity level.
    public func setStrokeColor(cyan: Double, magenta: Double, yellow: Double, black: Double, alpha: Double) {
        self.strokeColorSpace = .genericCMYK
        self.strokeColor = .init(cyan: cyan, magenta: magenta, yellow: yellow, black: black, alpha: alpha)
    }

    /// Sets the current stroke color to a value in the DeviceGray color space.
    /// 
    /// When you call this function, two things happen:
    ///   - Core Graphics sets the current stroke color space to DeviceGray. 
    ///     The DeviceGray color space is a single-dimension space in which color values are specified solely by the intensity of a gray value (from absolute black to absolute white).
    ///   - Core Graphics sets the current stroke color to the value you specify in the gray and alpha parameters.
    /// - Parameters:
    ///   - gray: A value that specifies the desired gray level.
    ///   - alpha: A value that specifies the opacity level.
    public func setStrokeColor(gray: Double, alpha: Double) {
        self.strokeColorSpace = .linearGray
        self.strokeColor = .init(gray: gray, alpha: alpha)
    }

    /// Sets the current stroke color to a value in the DeviceRGB color space.
    /// 
    /// When you call this function, two things happen:
    ///   - Core Graphics sets the current stroke color space to DeviceRGB.
    ///   - Core Graphics sets the current stroke color to the value specified by the red, green, blue, and alpha parameters.
    /// - Parameters:
    ///   - red: The red intensity value for the color to set.
    ///   - green: The green intensity value for the color to set. 
    ///   - blue: The blue intensity value for the color to set.
    ///   - alpha: A value that specifies the opacity level.
    public func setStrokeColor(red: Double, green: Double, blue: Double, alpha: Double) {
        self.strokeColorSpace = .genericRGBLinear
        self.strokeColor = .init(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Sets the stroke color space in a graphics context.
    /// 
    /// As a side effect when you call this function, Core Graphics assigns an appropriate initial value to the stroke color, based on the color space you specify. 
    /// To change this value, call ``setStrokeColor(_:)``. Note that the preferred API is now ``setStrokeColor(_:)``.
    /// - Parameter space: The new stroke color space. 
    public func setStrokeColorSpace(_ space: CGColorSpace) {
        self.strokeColorSpace = space
    }

    // MARK: - Working with the Current Transformation Matrix

    /// Returns the current transformation matrix.
    public var ctm: CGAffineTransform = .identity

    /// Rotates the user coordinate system in a context.
    /// 
    /// - Parameter angle: The angle, in radians, by which to rotate the coordinate space of the specified context. Positive values rotate counterclockwise and negative values rotate clockwise.)
    public func rotate(by angle: Double) {
        let rotation = CGAffineTransform.rotate(angle)
        self.ctm = self.ctm * rotation
    }

    /// Changes the scale of the user coordinate system in a context.
    /// - Parameters:
    ///   - sx: The factor by which to scale the x-axis of the coordinate space of the specified context.
    ///   - sy: The factor by which to scale the y-axis of the coordinate space of the specified context.
    public func scaleBy(x sx: Double, y sy: Double) {
        let scaling = CGAffineTransform.scale(sx, sy)
        self.ctm = self.ctm * scaling
    }

    /// Changes the origin of the user coordinate system in a context.
    /// - Parameters:
    ///   - tx: The amount to displace the x-axis of the coordinate space, in units of the user space, of the specified context.
    ///   - ty: The amount to displace the y-axis of the coordinate space, in units of the user space, of the specified context.
    public func translateBy(x tx: Double, y ty: Double)  {
        let translation = CGAffineTransform.translate(tx, ty)
        self.ctm = self.ctm * translation
    }

    /// Transforms the user coordinate system in a context using a specified matrix.
    /// 
    /// When you call this function, it concatenates (that is, it combines) two matrices, by multiplying them together. 
    /// The order in which matrices are concatenated is important, as the operations are not commutative. 
    /// The resulting CTM in the context is: CTMnew = CTMcontext * transform.
    /// - Parameter transform: The transformation matrix to apply to the specified context’s current transformation matrix.
    public func concatenate(_ transform: CGAffineTransform) {
        self.ctm = self.ctm * transform
    }

    // MARK: - Setting Path Drawing Options

    /// Sets the line width for a graphics context.
    /// 
    /// The default line width is 1 unit. 
    /// When stroked, the line straddles the path, with half of the total width on either side.
    /// - Parameter width: The new line width to use, in user space units. The value must be greater than 0.
    public func setLineWidth(_ width: Double = 1) {
        self.lineWidth = width
    }

    // MARK: - Saving and Restoring Graphics State

    /// Pushes a copy of the current graphics state onto the graphics state stack for the context.
    /// 
    /// Each graphics context maintains a stack of graphics states.
    /// Note that not all aspects of the current drawing environment are elements of the graphics state. 
    /// For example, the current path is not considered part of the graphics state and is therefore not saved when you call this function. 
    /// The graphics state parameters that are saved are:
    /// CTM (current transformation matrix), clip region, image interpolation quality, line width
    /// line join, miter limit, line cap, line dash, flatness, should anti-alias, rendering intent
    /// fill color space, stroke color space, fill color, stroke color, alpha value, font, font size
    /// character spacing, text drawing mode, shadow parameters, the pattern phase, the font smoothing parameter, blend mode.
    public func saveGState() {
        graphicsStateStack.append(currentGraphicsState)
    }

    /// Sets the current graphics state to the state most recently saved.
    /// 
    /// Core Graphics removes the graphics state at the top of the stack so that the most recently saved state becomes the current graphics state.
    public func restoreGState() {
        guard let state = graphicsStateStack.popLast() else {
            return
        }

        restoreGraphicsState(state)
    }

    /// Creates a value snapshot of the current graphics-state parameters.
    private var currentGraphicsState: CGGraphicsState {
        var state = CGGraphicsState()
        state.ctm = ctm
        state.fillColor = fillColor
        state.strokeColor = strokeColor
        state.fillColorSpace = fillColorSpace
        state.strokeColorSpace = strokeColorSpace
        state.lineWidth = lineWidth
        state.lineCap = lineCap
        state.lineJoin = lineJoin
        state.miterLimit = miterLimit
        state.lineDash = lineDash
        state.blendMode = blendMode
        state.interpolationQuality = interpolationQuality
        state.renderingIntent = renderingIntent
        state.clip = clip
        state.font = font?.fullName
        state.fontSize = fontSize
        state.characterSpacing = characterSpacing
        state.textDrawingMode = textDrawingMode
        return state
    }

    /// Restores the graphics-state parameters from a saved value snapshot.
    /// - Parameter state: The graphics state to restore.
    private func restoreGraphicsState(_ state: CGGraphicsState) {
        ctm = state.ctm
        fillColor = state.fillColor
        strokeColor = state.strokeColor
        fillColorSpace = state.fillColorSpace
        strokeColorSpace = state.strokeColorSpace
        lineWidth = state.lineWidth
        lineCap = state.lineCap
        lineJoin = state.lineJoin
        miterLimit = state.miterLimit
        lineDash = state.lineDash
        blendMode = state.blendMode
        interpolationQuality = state.interpolationQuality
        renderingIntent = state.renderingIntent
        clip = state.clip
        font = state.font.flatMap(CGFont.init)
        fontSize = state.fontSize
        characterSpacing = state.characterSpacing
        textDrawingMode = state.textDrawingMode
    }

    // MARK: - Managing a Graphics Context

    /// Forces all pending drawing operations in a window context to be rendered immediately to the destination device.
    /// 
    /// When you call this function, Core Graphics immediately flushes the current drawing to the destination device (for example, a screen). 
    /// Because the system software flushes a context automatically at the appropriate times, calling this function could have an adverse effect on performance. 
    /// Under normal conditions, you do not need to call this function.
    public func flush() {
        guard let renderTarget else { return }

        let commands = pendingDrawCommands
        pendingDrawCommands.removeAll(keepingCapacity: true)
        MainActor.assumeIsolated {
            commands.forEach(renderTarget.submit)
            renderTarget.flush()
        }
    }

    /// Marks a window context for update.
    /// 
    /// When you call this function, all drawing operations since the last update are flushed at the next regular opportunity. 
    /// Under normal conditions, you do not need to call this function.
    public func synchronize() {
    }

    var blendMode: CGBlendMode = .normal
    var renderingIntent: CGColorRenderingIntent = .defaultIntent

    /// Sets how sample values are composited by a graphics context.
    /// - Parameter mode: A blend mode.
    public func setBlendMode(_ mode: CGBlendMode) {
        blendMode = mode
    }

    /// Sets the rendering intent in the current graphics state.
    /// 
    /// The rendering intent specifies how to handle colors that are not located within the gamut of the destination color space of a graphics context. 
    /// If you do not explicitly set the rendering intent, Core Graphics uses perceptual rendering intent when drawing sampled images and relative colorimetric rendering intent for all other drawing.
    /// - Parameter intent: A rendering intent constant
    public func setRenderingIntent(_ intent: CGColorRenderingIntent) {
        renderingIntent = intent
    }

    // MARK: - Managing a Bitmap Graphics Context

    /// Obtains the bitmap information associated with a bitmap graphics context.
    public var bitmapInfo: CGBitmapInfo

    /// Returns the alpha information associated with the context, which indicates how a bitmap context handles the alpha component.
    public var alphaInfo: CGImageAlphaInfo

    /// Returns the bits per component of a bitmap context.
    public var bitsPerComponent: Int
    
    /// Returns the bits per pixel of a bitmap context.
    public var bitsPerPixel: Int
    
    /// Returns the bytes per row of a bitmap context.
    public var bytesPerRow: Int
    
    /// Returns the color space of a bitmap context.
    public var colorSpace: CGColorSpace?
    
    /// Returns a pointer to the image data associated with a bitmap context.
    public var data: Data
    
    /// Returns the height in pixels of a bitmap context.
    public var height: Int
    
    /// Returns the width in pixels of a bitmap context.
    public var width: Int
    
    /// Creates and returns a CGImage from the pixel data in a bitmap graphics context.
    public func makeImage() -> CGImage? {
        .init(
            width: width, 
            height: height, 
            bitsPerComponent: bitsPerComponent, 
            bitsPerPixel: bitsPerPixel, 
            bytesPerRow: bytesPerRow, 
            space: colorSpace ?? .genericRGBLinear, 
            bitmapInfo: bitmapInfo, 
            provider: CGDataProvider(data: data), 
            decode: nil, 
            shouldInterpolate: false, 
            intent: .defaultIntent
        )
    }
}