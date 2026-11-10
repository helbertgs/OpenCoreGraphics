import Foundation

/// A graphics path: a mathematical description of shapes or lines to be drawn in a graphics context.
/// 
/// CGPath functions to draw a path. 
/// To draw a Core Graphics path to a graphics context, you add the path to the graphics context by calling ``addPath(_:)`` and then call one of the context’s drawing functions—see ``CGContext``.
/// 
/// Each figure in the graphics path is constructed with a connected set of lines and Bézier curves, called a subpath. 
/// A subpath has an ordered set of path elements that represent single steps in the construction of the subpath. (For example, a line segment from one corner of a rectangle to another corner is a path element). 
/// Every subpath includes a starting point, which is the first point in the subpath. 
/// The path also maintains a current point, which is the last point in the last subpath.
/// 
/// To append a new subpath onto a mutable path, your application typically calls ``move(to:)`` to set the subpath’s starting point and initial current point, followed by a series of “add” calls (such as ``addLine(to:)``) to add line segments and curves to the subpath. 
/// As segments or curves are added to the subpath, the subpath’s current point is updated to point to the end of the last segment or curve to be added. 
/// The lines and curves of a subpath are always connected, but they are not required to form a closed set of lines. 
/// Your application explicitly closes a subpath by calling closeSubpath(). 
/// 
/// Closing the subpath adds a line segment that terminates at the subpath’s starting point, and also changes how those lines are rendered
public struct CGPath : Codable, Equatable, Hashable, Sendable {

    // MARK: - Instance Properties

    private(set) var subpath: [CGPathElement] = []

    // MARK: - Creating Graphics Paths

    /// Creates a mutable graphics path.
    public init() {
    }

    /// Returns whether two paths contain the same path elements and current point.
    /// - Parameters:
    ///   - lhs: The first path to compare.
    ///   - rhs: The second path to compare.
    /// - Returns: `true` when both paths have equivalent stored geometry.
    public static func == (lhs: CGPath, rhs: CGPath) -> Bool {
        lhs.subpath == rhs.subpath && lhs.currentPoint == rhs.currentPoint
    }

    /// Adds the path's stored geometry to a hash.
    /// - Parameter hasher: The hasher that receives this path's identity.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(subpath)
        hasher.combine(currentPoint)
    }

    /// Create a path of a rectangle.
    /// 
    /// This is a convenience function that creates a path of an rectangle. 
    /// Using this convenience function is more efficient than creating a mutable path and adding an rectangle to it.
    /// 
    /// Calling this function is equivalent to using rect.minX and related properties to find the corners of the rectangle, then using the move(to:), addLine(to:), and closeSubpath() functions to draw the rectangle.
    /// - Parameters:
    ///   - rect: The rectangle to add.
    ///   - transform: A pointer to an affine transformation matrix, or nil if no transformation is needed. If specified, Core Graphics applies the transformation to the rectangle before it is added to the path.
    public init(rect: CGRect, transform: CGAffineTransform? = nil) {
        addRect(rect, transform: transform ?? .identity)
    }

    /// Create a path of an ellipse.
    /// 
    /// This is a convenience function that creates a path of an ellipse. Using this convenience function is more efficient than creating a mutable path and adding an ellipse to it.
    /// The ellipse is approximated by a sequence of Bézier curves. 
    /// Its center is the midpoint of the rectangle defined by the rect parameter. 
    /// If the rectangle is square, then the ellipse is circular with a radius equal to one-half the width (or height) of the rectangle. 
    /// If the rect parameter specifies a rectangular shape, then the major and minor axes of the ellipse are defined by the width and height of the rectangle.
    /// 
    /// The ellipse forms a complete subpath of the path—that is, the ellipse drawing starts with a move-to operation and ends with a close-subpath operation, with all moves oriented in the clockwise direction. 
    /// If you supply an affine transform, then the constructed Bézier curves that define the ellipse are transformed before they are added to the path.
    /// - Parameters:
    ///   - rect: The rectangle that bounds the ellipse.
    ///   - transform: A pointer to an affine transformation matrix, or nil if no transformation is needed. If specified, Core Graphics applies the transformation to the ellipse before it is added to the path.
    public init(ellipseIn rect: CGRect, transform: CGAffineTransform? = nil) {
        addEllipse(in: rect, transform: transform ?? .identity)
    }

    /// Create an immutable path of a rounded rectangle.
    /// 
    /// This is a convenience function that creates a path of an rounded rectangle. 
    /// Using this convenience function is more efficient than creating a mutable path and adding an rectangle to it.
    /// 
    /// Each corner of the rounded rectangle is one-quarter of an ellipse with axes equal to the cornerWidth and cornerHeight parameters. 
    /// The rounded rectangle forms a complete subpath and is oriented in the clockwise direction.
    /// - Parameters:
    ///   - rect: The rectangle to add.
    ///   - cornerWidth: The width of the rounded corner sections.
    ///   - cornerHeight: The height of the rounded corner sections.
    ///   - transform: A pointer to an affine transformation matrix, or nil if no transformation is needed. If specified, Core Graphics applies the transformation to the rectangle before it is added to the path.
    public init(roundedRect rect: CGRect, cornerWidth: Double, cornerHeight: Double, transform: CGAffineTransform? = nil) {
        addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight, transform: transform ?? .identity)
    }

    // MARK: - Copying a Graphics Path

    /// Creates a copy of a graphics path.
    /// - Returns: A new, immutable copy of the specified path.
    public func copy() -> CGPath? {
        self
    }

    /// Creates a copy of a graphics path transformed by a transformation matrix.
    /// - Parameter transform: A pointer to an affine transformation matrix, or nil if no transformation is needed.
    /// - Returns: A copy of the path
    public func copy(using transform: CGAffineTransform) -> CGPath? {
        var copy = self
        copy.subpath = subpath.map { element in
            CGPathElement(type: element.type, points: element.points.map { $0.applying(transform) })
        }
        copy.currentPoint = subpath.isEmpty ? .zero : currentPoint.applying(transform)
        copy.recalculateBounds()
        return copy
    }

    // MARK: - Examining a Graphics Path

    /// Returns the bounding box containing all points in a graphics path.
    /// 
    /// The bounding box is the smallest rectangle completely enclosing all points in the path, including control points for Bézier and quadratic curves. 
    /// If the path is empty, this value is ``.null``.
    public private(set) var boundingBox: CGRect = .null

    /// Returns the bounding box of a graphics path.
    /// 
    /// The path bounding box is the smallest rectangle completely enclosing all points in the path but not including control points for Bézier and quadratic curves. 
    /// If the path is empty, this value is ``.null``.
    public private(set) var boundingBoxOfPath: CGRect = .null

    /// Returns the current point in a graphics path.
    /// 
    /// If the path is empty—that is, if it has no elements—this returns ``.zero``. 
    /// To determine whether a path is empty, use isEmpty.
    public private(set) var currentPoint: CGPoint = .zero

    /// Returns whether the specified point is interior to the path.
    /// 
    /// A point is contained in a path if it would be inside the painted region when the path is filled.
    /// - Parameters:
    ///   - point: The point to check.
    ///   - rule: The rule for determining which areas to treat as the interior of the path. Defaults to the ``.winding`` rule if not specified.
    ///   - transform: An affine transform to apply to the point before checking for containment in the path. Defaults to the ``.identity`` transform if not specified.
    /// - Returns: true if the point is interior to the path; otherwise, false.
    public func contains(_ point: CGPoint, using rule: CGPathFillRule = .winding, transform: CGAffineTransform = .identity) -> Bool {
        let transformedPoint = point.applying(transform)
        var windingNumber = 0
        var crossingCount = 0

        for polygon in flattenedSubpaths() where polygon.count > 1 {
            for index in polygon.indices {
                let start = polygon[index]
                let end = polygon[(index + 1) % polygon.count]
                if isOnSegment(transformedPoint, start: start, end: end) {
                    return true
                }

                if (start.y > transformedPoint.y) != (end.y > transformedPoint.y) {
                    let crossingX = start.x + (transformedPoint.y - start.y)
                        * (end.x - start.x) / (end.y - start.y)
                    if transformedPoint.x < crossingX {
                        crossingCount += 1
                    }
                }

                let cross = (end.x - start.x) * (transformedPoint.y - start.y)
                    - (transformedPoint.x - start.x) * (end.y - start.y)
                if start.y <= transformedPoint.y, end.y > transformedPoint.y, cross > 0 {
                    windingNumber += 1
                } else if start.y > transformedPoint.y, end.y <= transformedPoint.y, cross < 0 {
                    windingNumber -= 1
                }
            }
        }

        switch rule {
        case .evenOdd:
            return crossingCount.isMultiple(of: 2) == false
        case .winding:
            return windingNumber != 0
        }
    }

    /// Indicates whether or not a graphics path is empty.
    /// 
    /// An empty path contains no elements.
    public var isEmpty: Bool {
        subpath.isEmpty
    }

    // MARK: - Constructing a Graphics Path

    /// Begins a new subpath at the specified point.
    /// 
    /// The specified point becomes the start point of a new subpath. 
    /// The current point is set to this start point.
    /// - Parameters:
    ///   - point: The point, in user space coordinates, at which to start a new subpath.
    ///   - transform: An affine transform to apply to the point before adding to the path.
    mutating public func move(to point: CGPoint, transform: CGAffineTransform = .identity) {
        let element = CGPathElement(type: .moveToPoint, points: [point.applying(transform)])
        append(element)

        currentPoint = point.applying(transform)
    }

    /// Appends a straight line segment from the current point to the specified point.
    /// 
    /// After adding the line segment, the current point is set to the endpoint of the line segment.
    /// - Parameters:
    ///   - point: The location, in user space coordinates, for the end of the new line segment.
    ///   - transform: An affine transform to apply to the point before adding to the path. 
    mutating public func addLine(to point: CGPoint, transform: CGAffineTransform = .identity) {
        let element = CGPathElement(type: .addLineToPoint, points: [ currentPoint, point.applying(transform)])
        append(element)
        currentPoint = point.applying(transform)
    }

    /// Adds a sequence of connected straight-line segments to the path.
    /// 
    /// Calling this convenience method is equivalent to calling the ``move(to:transform:)`` method with the first value in the points array, then calling the ``addLine(to:transform:)`` method for each subsequent point until the array is exhausted. 
    /// After calling this method, the path’s current point is the last point in the array.
    /// - Parameters:
    ///   - points: An array of values that specify the start and end points of the line segments to draw. Each point in the array specifies a position in user space. The first point in the array specifies the initial starting point.
    ///   - transform: An affine transform to apply to the points before adding to the path.
    mutating public func addLines(between points: [CGPoint], transform: CGAffineTransform = .identity) {
        guard let firstPoint = points.first else { return }
        move(to: firstPoint, transform: transform)
        points.dropFirst().forEach { point in
            addLine(to: point, transform: transform)
        }
    }

    /// Adds a rectangular subpath to the path.
    /// 
    /// This is a convenience function that adds a rectangle to a path, starting by moving to the bottom-left corner and then adding lines counter-clockwise to create a rectangle, closing the subpath.
    /// - Parameters:
    ///   - rect: A rectangle, specified in user space coordinates.
    ///   - transform: An affine transform to apply to the rectangle before adding to the path.
    mutating public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {
        let bottomLeft = CGPoint(x: rect.minX, y: rect.minY).applying(transform)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.minY).applying(transform)
        let topRight = CGPoint(x: rect.maxX, y: rect.maxY).applying(transform)
        let topLeft = CGPoint(x: rect.minX, y: rect.maxY).applying(transform)

        let element = CGPathElement(type: .addRectToPoint, points: [
            bottomLeft,
            bottomRight,
            topRight,
            topLeft,
        ])

        append(element)
        currentPoint = bottomLeft
    }

    /// Adds a set of rectangular subpaths to the path.
    /// 
    /// Calling this convenience method is equivalent to repeatedly calling the addRect(_:transform:) method for each rectangle in the array.
    /// - Parameters:
    ///   - rects: An array of rectangles, specified in user space coordinates.
    ///   - transform: An affine transform to apply to the rectangles before adding to the path. 
    mutating public func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) {
        rects.forEach { rect in
            addRect(rect, transform: transform)
        }
    }

    /// Adds an ellipse that fits inside the specified rectangle.
    /// 
    /// The ellipse is approximated by a sequence of Bézier curves. 
    /// Its center is the midpoint of the rectangle defined by the rect parameter. 
    /// If the rectangle is square, then the ellipse is circular with a radius equal to one-half the width (or height) of the rectangle. 
    /// If the rect parameter specifies a rectangular shape, then the major and minor axes of the ellipse are defined by the width and height of the rectangle.
    /// 
    /// The ellipse forms a complete subpath of the path—that is, the ellipse drawing starts with a move-to operation and ends with a close-subpath operation, with all moves oriented in the clockwise direction.
    /// - Parameters:
    ///   - rect: A rectangle that defines the area for the ellipse to fit in.
    ///   - transform: An affine transform to apply to the ellipse before adding to the path.
    mutating public func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        let rx = rect.width / 2.0
        let ry = rect.height / 2.0
        let cx = rect.midX
        let cy = rect.midY
        let kappa: CGFloat = 0.552284749831

        let start = CGPoint(x: cx + rx, y: cy).applying(transform)
        move(to: start)

        addCurve(
            to: CGPoint(x: cx, y: cy + ry).applying(transform),
            control1: CGPoint(x: cx + rx, y: cy + kappa * ry).applying(transform),
            control2: CGPoint(x: cx + kappa * rx, y: cy + ry).applying(transform)
        )
        addCurve(
            to: CGPoint(x: cx - rx, y: cy).applying(transform),
            control1: CGPoint(x: cx - kappa * rx, y: cy + ry).applying(transform),
            control2: CGPoint(x: cx - rx, y: cy + kappa * ry).applying(transform)
        )
        addCurve(
            to: CGPoint(x: cx, y: cy - ry).applying(transform),
            control1: CGPoint(x: cx - rx, y: cy - kappa * ry).applying(transform),
            control2: CGPoint(x: cx - kappa * rx, y: cy - ry).applying(transform)
        )
        addCurve(
            to: start,
            control1: CGPoint(x: cx + kappa * rx, y: cy - ry).applying(transform),
            control2: CGPoint(x: cx + rx, y: cy - kappa * ry).applying(transform)
        )
        closeSubpath()
    }

    /// Adds a subpath to the path, in the shape of a rectangle with rounded corners.
    /// 
    /// This convenience method is equivalent to a move operation to start the subpath followed by a series of arc and line operations that construct the rounded rectangle. 
    /// Each corner of the rounded rectangle is one-quarter of an ellipse with axes equal to the ``cornerWidth`` and ``cornerHeight`` parameters. 
    /// The rounded rectangle forms a closed subpath oriented in the clockwise direction.
    /// - Parameters:
    ///   - rect: The rectangle to add, specified in user space coordinates.
    ///   - cornerWidth: The horizontal size, in user space coordinates, for rounded corner sections.
    ///   - cornerHeight: The vertical size, in user space coordinates, for rounded corner sections.
    ///   - transform: An affine transform to apply to the rectangle before adding to the path. 
    mutating public func addRoundedRect(in rect: CGRect, cornerWidth: Double, cornerHeight: Double, transform: CGAffineTransform = .identity) {
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        let cw = CGFloat(cornerWidth), ch = CGFloat(cornerHeight)
        let kappa: CGFloat = 0.552284749831

        move(to: CGPoint(x: minX + cw, y: minY), transform: transform)
        addLine(to: CGPoint(x: maxX - cw, y: minY), transform: transform)
        addCurve(
            to: CGPoint(x: maxX, y: minY + ch),
            control1: CGPoint(x: maxX - cw + kappa * cw, y: minY),
            control2: CGPoint(x: maxX, y: minY + ch - kappa * ch),
            transform: transform
        )
        addLine(to: CGPoint(x: maxX, y: maxY - ch), transform: transform)
        addCurve(
            to: CGPoint(x: maxX - cw, y: maxY),
            control1: CGPoint(x: maxX, y: maxY - ch + kappa * ch),
            control2: CGPoint(x: maxX - cw + kappa * cw, y: maxY),
            transform: transform
        )
        addLine(to: CGPoint(x: minX + cw, y: maxY), transform: transform)
        addCurve(
            to: CGPoint(x: minX, y: maxY - ch),
            control1: CGPoint(x: minX + cw - kappa * cw, y: maxY),
            control2: CGPoint(x: minX, y: maxY - ch + kappa * ch),
            transform: transform
        )
        addLine(to: CGPoint(x: minX, y: minY + ch), transform: transform)
        addCurve(
            to: CGPoint(x: minX + cw, y: minY),
            control1: CGPoint(x: minX, y: minY + ch - kappa * ch),
            control2: CGPoint(x: minX + cw - kappa * cw, y: minY),
            transform: transform
        )
        closeSubpath()
    }

    /// Adds an arc of a circle to the path, specified with a radius and angles.
    /// 
    /// This method calculates starting and ending points using the radius and angles you specify, uses a sequence of cubic Bézier curves to approximate a segment of a circle between those points, and then appends those curves to the path.
    /// The clockwise parameter determines the direction in which the arc is created; the actual direction of the final path is dependent on the transform parameter and the current transform of a context where the path is drawn. 
    /// In a flipped coordinate system (the default for ``UIView`` drawing methods in iOS), specifying a clockwise arc results in a counterclockwise arc after the transformation is applied.
    /// 
    /// If the path already contains a subpath, this method adds a line connecting the current point to the starting point of the arc. 
    /// If the current path is empty, this method creates a new subpath whose starting point is the starting point of the arc. 
    /// The ending point of the arc becomes the new current point of the path.
    /// - Parameters:
    ///   - center: The center of the arc, in user space coordinates.
    ///   - radius: The radius of the arc, in user space coordinates.
    ///   - startAngle: The angle to the starting point of the arc, measured in radians from the positive x-axis.
    ///   - endAngle: The angle to the end point of the arc, measured in radians from the positive x-axis.
    ///   - clockwise: true to make a clockwise arc; false to make a counterclockwise arc.
    ///   - transform: An affine transform to apply to the arc before adding to the path.
    mutating public func addArc(center: CGPoint, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool, transform: CGAffineTransform = .identity) {
        guard center.x.isFinite, center.y.isFinite, radius.isFinite,
              startAngle.isFinite, endAngle.isFinite else {
            return
        }

        let radius = abs(radius)
        let sweep = normalizedArcSweep(from: startAngle, to: endAngle, clockwise: clockwise)
        let startPoint = CGPoint(
            x: center.x + cos(startAngle) * radius,
            y: center.y + sin(startAngle) * radius
        )
        if subpath.isEmpty {
            move(to: startPoint, transform: transform)
        } else {
            addLine(to: startPoint, transform: transform)
        }
        guard sweep != 0, radius != 0 else { return }

        let segmentCount = max(1, Int(ceil(abs(sweep) / (.pi / 2) - 1e-12)))
        let angleStep = sweep / Double(segmentCount)
        var segmentStart = startAngle
        for _ in 0..<segmentCount {
            let segmentEnd = segmentStart + angleStep
            let controlScale = 4.0 / 3.0 * tan(angleStep / 4.0)
            let start = pointOnCircle(center: center, radius: radius, angle: segmentStart)
            let end = pointOnCircle(center: center, radius: radius, angle: segmentEnd)
            let control1 = CGPoint(
                x: start.x - controlScale * radius * sin(segmentStart),
                y: start.y + controlScale * radius * cos(segmentStart)
            )
            let control2 = CGPoint(
                x: end.x + controlScale * radius * sin(segmentEnd),
                y: end.y - controlScale * radius * cos(segmentEnd)
            )
            addCurve(to: end, control1: control1, control2: control2, transform: transform)
            segmentStart = segmentEnd
        }
    }

    /// Adds an arc of a circle to the path, specified with a radius and two tangent lines.
    /// 
    /// This method calculates two tangent lines—the first from the current point to the tangent1End point, and the second from the tangent1End point to the tangent2End point—then calculates the start and end points for a circular arc of the specified radius such that the arc is tangent to both lines. 
    /// Finally, this method approximates that arc with a sequence of cubic Bézier curves and appends those curves to the path.
    /// 
    /// If the starting point of the arc (that is, the point where a circle of the specified radius must meet the first tangent line in order to also be tangent to the second line) is not the current point, this method appends a straight line segment from the current point to the starting point of the arc.
    /// The ending point of the arc (that is, the point where a circle of the specified radius must meet the second tangent line in order to also be tangent to the first line) becomes the new current point of the path.
    /// - Parameters:
    ///   - tangent1End: The end point, in user space coordinates, for the first tangent line to be used in constructing the arc. (The start point for this tangent line is the path’s current point.)
    ///   - tangent2End: The end point, in user space coordinates, for the second tangent line to be used in constructing the arc. (The start point for this tangent line is the tangent1End point.)
    ///   - radius: The radius of the arc, in user space coordinates.
    ///   - transform: An affine transform to apply to the arc before adding to the path.
    mutating public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: Double,transform: CGAffineTransform = .identity) {
        guard radius.isFinite, tangent1End.x.isFinite, tangent1End.y.isFinite,
              tangent2End.x.isFinite, tangent2End.y.isFinite else {
            return
        }

        guard subpath.isEmpty == false else {
            move(to: tangent1End, transform: transform)
            addLine(to: tangent2End, transform: transform)
            return
        }

        let start = currentPoint
        let incoming = CGPoint(x: tangent1End.x - start.x, y: tangent1End.y - start.y)
        let outgoing = CGPoint(x: tangent2End.x - tangent1End.x, y: tangent2End.y - tangent1End.y)
        let incomingLength = hypot(incoming.x, incoming.y)
        let outgoingLength = hypot(outgoing.x, outgoing.y)
        guard incomingLength > Double.ulpOfOne, outgoingLength > Double.ulpOfOne else {
            addLine(to: tangent1End, transform: transform)
            addLine(to: tangent2End, transform: transform)
            return
        }

        let firstDirection = CGPoint(x: -incoming.x / incomingLength, y: -incoming.y / incomingLength)
        let secondDirection = CGPoint(x: outgoing.x / outgoingLength, y: outgoing.y / outgoingLength)
        let directionDot = firstDirection.x * secondDirection.x + firstDirection.y * secondDirection.y
        let directionCross = firstDirection.x * secondDirection.y - firstDirection.y * secondDirection.x
        let angle = atan2(abs(directionCross), directionDot)
        let radius = abs(radius)
        guard radius > 0, angle > 1e-10, abs(.pi - angle) > 1e-10 else {
            addLine(to: tangent1End, transform: transform)
            addLine(to: tangent2End, transform: transform)
            return
        }

        let tangentDistance = radius / tan(angle / 2)
        let tangentStart = CGPoint(
            x: tangent1End.x + firstDirection.x * tangentDistance,
            y: tangent1End.y + firstDirection.y * tangentDistance
        )
        let tangentEnd = CGPoint(
            x: tangent1End.x + secondDirection.x * tangentDistance,
            y: tangent1End.y + secondDirection.y * tangentDistance
        )
        let bisectorLength = hypot(
            firstDirection.x + secondDirection.x,
            firstDirection.y + secondDirection.y
        )
        guard bisectorLength > Double.ulpOfOne else {
            addLine(to: tangent1End, transform: transform)
            addLine(to: tangent2End, transform: transform)
            return
        }
        let centerDistance = radius / sin(angle / 2)
        let center = CGPoint(
            x: tangent1End.x + (firstDirection.x + secondDirection.x) / bisectorLength * centerDistance,
            y: tangent1End.y + (firstDirection.y + secondDirection.y) / bisectorLength * centerDistance
        )
        let startAngle = atan2(tangentStart.y - center.y, tangentStart.x - center.x)
        let endAngle = atan2(tangentEnd.y - center.y, tangentEnd.x - center.x)
        let clockwise = directionCross > 0
        addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise,
            transform: transform
        )
    }

    /// Adds an arc of a circle to the path, specified with a radius and a difference in angle.
    /// 
    /// This method calculates starting and ending points using the radius and angles you specify, uses a sequence of cubic Bézier curves to approximate a segment of a circle between those points, and then appends those curves to the path.
    /// 
    /// The delta parameter determines both the length of the arc the direction in which the arc is created; the actual direction of the final path is dependent on the transform parameter and the current transform of a context where the path is drawn. 
    /// In a flipped coordinate system (the default for ``UIView`` drawing methods in iOS), specifying a clockwise arc results in a counterclockwise arc after the transformation is applied.
    /// 
    /// If the path already contains a subpath, this method adds a line connecting the current point to the starting point of the arc. 
    /// If the current path is empty, this method creates a new subpath whose starting point is the starting point of the arc. 
    /// The ending point of the arc becomes the new current point of the path.
    /// - Parameters:
    ///   - center: The center of the arc, in user space coordinates.
    ///   - radius: The radius of the arc, in user space coordinates.
    ///   - startAngle: The angle to the starting point of the arc, measured in radians from the positive x-axis.
    ///   - delta: The difference, measured in radians, between the starting angle and ending angle of the arc. A positive value creates a counter-clockwise arc (in user space coordinates), and vice versa.
    ///   - transform: An affine transform to apply to the arc before adding to the path.
    mutating public func addRelativeArc(center: CGPoint, radius: Double, startAngle: Double, delta: Double, transform: CGAffineTransform = .identity) {
        addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: startAngle + delta,
            clockwise: delta < 0,
            transform: transform
        )
    }

    /// Adds a cubic Bézier curve to the path, with the specified end point and control points.
    /// 
    /// This method constructs a curve starting from the path’s current point and ending at the specified end point, with curvature defined by the two control points. 
    /// After this method appends that curve to the current path, the end point of the curve becomes the path’s current point.
    /// - Parameters:
    ///   - end: The point, in user space coordinates, at which to end the curve.
    ///   - control1: The first control point of the curve, in user space coordinates.
    ///   - control2: The second control point of the curve, in user space coordinates.
    ///   - transform: An affine transform to apply to the curve before adding to the path.
    mutating public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint, transform: CGAffineTransform = .identity) {
        let element = CGPathElement(
            type: .addCurveToPoint,
            points: [
                currentPoint,
                control1.applying(transform),
                control2.applying(transform),
                end.applying(transform)
            ]
        )
        append(element)
        currentPoint = end.applying(transform)
    }

    /// Adds a quadratic Bézier curve to the path, with the specified end point and control point.
    /// 
    /// This method constructs a curve starting from the path’s current point and ending at the specified end point, with curvature defined by the control point. 
    /// After this method appends that curve to the current path, the end point of the curve becomes the path’s current point.
    /// - Parameters:
    ///   - end: The point, in user space coordinates, at which to end the curve.
    ///   - control: The control point of the curve, in user space coordinates.
    ///   - transform: An affine transform to apply to the curve before adding to the path.
    mutating public func addQuadCurve(to end: CGPoint, control: CGPoint, transform: CGAffineTransform = .identity) {
        let element = CGPathElement(
            type: .addQuadCurveToPoint,
            points: [
                currentPoint,
                control.applying(transform),
                end.applying(transform)
            ]
        )
        append(element)
        currentPoint = end.applying(transform)
    }

    /// Appends another path object to the path.
    /// 
    /// If the path parameter is a non-empty empty path, its path elements are appended in order to this path. 
    /// Afterward, the start point and current point of this path are those of the last subpath in the path parameter.
    /// - Parameters:
    ///   - path: The path to add.
    ///   - transform: An affine transform to apply to the path parameter before adding to this path.
    mutating public func addPath(_ path: CGPath, transform: CGAffineTransform = .identity) {
        for element in path.subpath {
            let transformedPoints = element.points.map { $0.applying(transform) }
            let newElement = CGPathElement(type: element.type, points: transformedPoints)
            append(newElement)
        }
        if let last = path.subpath.last, let lastPoint = last.points.last {
            currentPoint = lastPoint
        }
    }

    /// Closes and completes a subpath in a mutable graphics path.
    /// 
    /// Appends a line from the current point to the starting point of the current subpath and ends the subpath. 
    /// After closing the subpath, your application can begin a new subpath without first calling ``move(to:)``. 
    /// In this case, a new subpath is implicitly created with a starting and current point equal to the previous subpath’s starting point.
    mutating public func closeSubpath() {
        guard subpath.last?.type != .closeSubpath,
              let startingElement = subpath.last(where: { $0.type == .moveToPoint || $0.type == .addRectToPoint }),
              let startingPoint = startingElement.points.first else {
            return
        }

        let element = CGPathElement(type: .closeSubpath, points: [])
        append(element)
        currentPoint = startingPoint
    }
}

private extension CGPath {
    /// Appends one element and expands both cached bounding rectangles.
    mutating func append(_ element: CGPathElement) {
        subpath.append(element)
        boundingBox = union(boundingBox, calculatedBounds(for: element, includingControlPoints: true))
        boundingBoxOfPath = union(boundingBoxOfPath, calculatedBounds(for: element, includingControlPoints: false))
    }

    /// Recomputes the control-point and geometric bounds from all path elements.
    mutating func recalculateBounds() {
        boundingBox = calculatedBounds(includingControlPoints: true)
        boundingBoxOfPath = calculatedBounds(includingControlPoints: false)
    }

    /// Calculates either control-point bounds or the actual bounds of the path curves.
    func calculatedBounds(includingControlPoints: Bool) -> CGRect {
        subpath.reduce(.null) { bounds, element in
            union(bounds, calculatedBounds(for: element, includingControlPoints: includingControlPoints))
        }
    }

    /// Calculates the control-point or geometric bounds for one path element.
    func calculatedBounds(for element: CGPathElement, includingControlPoints: Bool) -> CGRect {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity

        func include(_ point: CGPoint) {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        let points = element.points
        if includingControlPoints {
            points.forEach(include)
        }

        switch element.type {
        case .moveToPoint, .addLineToPoint, .addRectToPoint:
            points.forEach(include)
        case .addQuadCurveToPoint:
            guard points.count >= 3 else { return .null }
            let start = points[0]
            let control = points[1]
            let end = points[2]
            include(start)
            include(end)
            for t in quadraticExtrema(start.x, control.x, end.x) +
                quadraticExtrema(start.y, control.y, end.y) {
                include(quadraticPoint(start, control, end, at: t))
            }
        case .addCurveToPoint:
            guard points.count >= 4 else { return .null }
            let start = points[0]
            let control1 = points[1]
            let control2 = points[2]
            let end = points[3]
            include(start)
            include(end)
            for t in cubicExtrema(start.x, control1.x, control2.x, end.x) +
                cubicExtrema(start.y, control1.y, control2.y, end.y) {
                include(cubicPoint(start, control1, control2, end, at: t))
            }
        case .none, .closeSubpath:
            break
        }

        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Combines two rectangles while preserving the null rectangle as an identity value.
    func union(_ lhs: CGRect, _ rhs: CGRect) -> CGRect {
        guard lhs.isNull == false else { return rhs }
        guard rhs.isNull == false else { return lhs }
        let minX = min(lhs.minX, rhs.minX)
        let minY = min(lhs.minY, rhs.minY)
        let maxX = max(lhs.maxX, rhs.maxX)
        let maxY = max(lhs.maxY, rhs.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Returns the signed sweep for a single directed revolution or less.
    func normalizedArcSweep(from startAngle: Double, to endAngle: Double, clockwise: Bool) -> Double {
        let rawSweep = endAngle - startAngle
        guard rawSweep != 0 else { return 0 }
        let fullRevolution = 2 * Double.pi
        guard rawSweep.isFinite, abs(rawSweep) < fullRevolution else {
            return clockwise ? -fullRevolution : fullRevolution
        }

        if clockwise {
            return rawSweep > 0 ? rawSweep - fullRevolution : rawSweep
        }
        return rawSweep < 0 ? rawSweep + fullRevolution : rawSweep
    }

    /// Returns a point on a circle at the specified angle.
    func pointOnCircle(center: CGPoint, radius: Double, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    /// Converts each subpath to line segments suitable for point-in-path testing.
    func flattenedSubpaths() -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []

        func finishCurrentSubpath() {
            guard current.isEmpty == false else { return }
            result.append(current)
            current.removeAll(keepingCapacity: true)
        }

        for element in subpath {
            let points = element.points
            switch element.type {
            case .moveToPoint:
                finishCurrentSubpath()
                if let point = points.first {
                    current = [point]
                }
            case .addLineToPoint:
                guard let start = points.first, let end = points.last else { continue }
                if current.isEmpty {
                    current.append(start)
                } else if current.last != start {
                    current.append(start)
                }
                current.append(end)
            case .addQuadCurveToPoint:
                guard points.count >= 3 else { continue }
                let start = points[0]
                let control = points[1]
                let end = points[2]
                if current.isEmpty {
                    current.append(start)
                } else if current.last != start {
                    current.append(start)
                }
                for step in 1...32 {
                    current.append(quadraticPoint(start, control, end, at: Double(step) / 32))
                }
            case .addCurveToPoint:
                guard points.count >= 4 else { continue }
                let start = points[0]
                let control1 = points[1]
                let control2 = points[2]
                let end = points[3]
                if current.isEmpty {
                    current.append(start)
                } else if current.last != start {
                    current.append(start)
                }
                for step in 1...32 {
                    current.append(cubicPoint(start, control1, control2, end, at: Double(step) / 32))
                }
            case .addRectToPoint:
                finishCurrentSubpath()
                current = points
            case .closeSubpath:
                finishCurrentSubpath()
            case .none:
                break
            }
        }

        finishCurrentSubpath()
        return result
    }

    /// Determines whether a point lies on a line segment within floating-point tolerance.
    func isOnSegment(_ point: CGPoint, start: CGPoint, end: CGPoint) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let cross = (point.x - start.x) * dy - (point.y - start.y) * dx
        let tolerance = 1e-10 * max(1, max(abs(dx), abs(dy)))
        return abs(cross) <= tolerance
            && point.x >= min(start.x, end.x) - tolerance
            && point.x <= max(start.x, end.x) + tolerance
            && point.y >= min(start.y, end.y) - tolerance
            && point.y <= max(start.y, end.y) + tolerance
    }

    /// Returns interior parameter values where a quadratic component reaches an extremum.
    func quadraticExtrema(_ start: Double, _ control: Double, _ end: Double) -> [Double] {
        let denominator = start - 2 * control + end
        guard abs(denominator) > Double.ulpOfOne else { return [] }
        let t = (start - control) / denominator
        return t > 0 && t < 1 ? [t] : []
    }

    /// Returns interior parameter values where a cubic component reaches an extremum.
    func cubicExtrema(_ start: Double, _ control1: Double, _ control2: Double, _ end: Double) -> [Double] {
        let a = -start + 3 * control1 - 3 * control2 + end
        let b = 2 * (start - 2 * control1 + control2)
        let c = control1 - start

        if abs(a) <= Double.ulpOfOne {
            guard abs(b) > Double.ulpOfOne else { return [] }
            let t = -c / b
            return t > 0 && t < 1 ? [t] : []
        }

        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return [] }
        let root = sqrt(discriminant)
        return [(-b + root) / (2 * a), (-b - root) / (2 * a)].filter { $0 > 0 && $0 < 1 }
    }

    /// Evaluates a quadratic Bézier curve at a normalized parameter value.
    func quadraticPoint(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint, at t: Double) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }

    /// Evaluates a cubic Bézier curve at a normalized parameter value.
    func cubicPoint(
        _ start: CGPoint,
        _ control1: CGPoint,
        _ control2: CGPoint,
        _ end: CGPoint,
        at t: Double
    ) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * inverse * start.x
                + 3 * inverse * inverse * t * control1.x
                + 3 * inverse * t * t * control2.x
                + t * t * t * end.x,
            y: inverse * inverse * inverse * start.y
                + 3 * inverse * inverse * t * control1.y
                + 3 * inverse * t * t * control2.y
                + t * t * t * end.y
        )
    }
}

extension CGPath {
    /// The type of element found in a path.
    public enum CGPathElementType : String, Codable, Equatable, Hashable, Sendable {
        /// The path element type is not specified.
        case none
        
        /// The path element that starts a new subpath.
        case moveToPoint

        /// The path element that adds a line from the current point to a new point.
        case addLineToPoint

        /// The path element that adds a quadratic curve from the current point to the specified point.
        case addQuadCurveToPoint

        /// The path element that adds a cubic curve from the current point to the specified point.
        case addCurveToPoint

        /// The path element that adds a line from the current point to the specified point and then closes the subpath.
        case addRectToPoint

        /// The path element that closes and completes a subpath. 
        /// The element does not contain any points.
        case closeSubpath
    }
}

extension CGPath {
    /// A data structure that provides information about a path element.
    public struct CGPathElement : Codable, Equatable, Hashable, Sendable {

        // MARK: - Instance Properties

        /// An element type (or operation).
        public let type: CGPathElementType

        /// An array of one or more points that serve as arguments.
        public let points: [CGPoint]

        // MARK: - Initializers

        /// Crete a element
        /// - Parameters:
        ///   - type: An element type
        ///   - points: An array of one or more points that serve as arguments.
        public init(type: CGPathElementType, points: [CGPoint]) {
            self.type = type
            self.points = points
        }
    }
}

extension CGPath {
    /// Rules for determining which regions are interior to a path, used by the ``fillPath(using:)`` and ``clip(using:)`` methods.
    /// 
    /// When filling a path, regions that a fill rule defines as interior to the path are painted.
    ///  When clipping with a path, regions interior to the path remain visible after clipping.
    public enum CGPathFillRule : String, Codable, Equatable, Hashable, Sendable {
        // MARK: - Enumeration Cases

        /// A rule that considers a region to be interior to a path based on the number of times it is enclosed by path elements.
        case evenOdd

        /// A rule that considers a region to be interior to a path if the winding number for that region is nonzero.
        case winding
    }
}

extension CGPath {
    /// Options for rendering a path.
    /// 
    /// You can pass a path drawing mode constant to the function ``drawPath(using:)`` to specify how Core Graphics should paint a graphics context’s current path.
    public enum CGPathDrawingMode : String, Codable, Equatable, Hashable, Sendable {

        /// Render the area contained within the path using the non-zero winding number rule.
        case fill

        /// Render the area within the path using the even-odd rule.
        case eoFill

        /// Render a line along the path.
        case stroke

        /// First fill and then stroke the path, using the nonzero winding number rule.
        case fillStroke

        /// First fill and then stroke the path, using the even-odd rule.
        case eoFillStroke
    }
}

extension CGPath.CGPathElement : CustomDebugStringConvertible {
    public var debugDescription: String {
        var result = "CGPathElement: \(type)"
        for point in points {
            result += "\n\t\(point)"
        }
        return result
    }
}