/// Converts Bézier curves in a path into line segments within a geometric tolerance.
enum PathFlattener {
    /// Flattens every subpath into connected line segments.
    /// - Parameters:
    ///   - path: The path whose curves will be approximated.
    ///   - tolerance: The maximum allowed distance between each curve's control hull and its line segments.
    /// - Returns: One polyline for each nonempty subpath.
    /// - Precondition: `tolerance` is finite and greater than zero.
    static func flatten(_ path: CGPath, tolerance: Double = 0.25) -> [Polyline] {
        precondition(tolerance.isFinite && tolerance > 0, "Flattening tolerance must be finite and greater than zero.")

        var polylines: [Polyline] = []
        var points: [CGPoint] = []
        var isClosed = false

        func finishCurrentPolyline() {
            guard points.isEmpty == false else { return }
            polylines.append(Polyline(points: points, isClosed: isClosed))
            points.removeAll(keepingCapacity: true)
            isClosed = false
        }

        func appendStartPoint(_ start: CGPoint) {
            if points.isEmpty {
                points.append(start)
            } else if points.last != start {
                points.append(start)
            }
        }

        for element in path.subpath {
            switch element.type {
            case .moveToPoint:
                finishCurrentPolyline()
                if let point = element.points.first {
                    points = [point]
                }
            case .addLineToPoint:
                guard element.points.count >= 2 else { continue }
                appendStartPoint(element.points[0])
                if let end = element.points.last {
                    points.append(end)
                }
            case .addQuadCurveToPoint:
                guard element.points.count >= 3 else { continue }
                appendStartPoint(element.points[0])
                flattenQuadratic(
                    element.points[0],
                    element.points[1],
                    element.points[2],
                    tolerance: tolerance,
                    depth: 0,
                    into: &points
                )
            case .addCurveToPoint:
                guard element.points.count >= 4 else { continue }
                appendStartPoint(element.points[0])
                flattenCubic(
                    element.points[0],
                    element.points[1],
                    element.points[2],
                    element.points[3],
                    tolerance: tolerance,
                    depth: 0,
                    into: &points
                )
            case .addRectToPoint:
                finishCurrentPolyline()
                if element.points.isEmpty == false {
                    polylines.append(Polyline(points: element.points, isClosed: true))
                }
            case .closeSubpath:
                isClosed = true
                finishCurrentPolyline()
            case .none:
                continue
            }
        }

        finishCurrentPolyline()
        return polylines
    }

    /// Subdivides a quadratic Bézier curve until its control point is within tolerance of its chord.
    private static func flattenQuadratic(
        _ start: CGPoint,
        _ control: CGPoint,
        _ end: CGPoint,
        tolerance: Double,
        depth: Int,
        into points: inout [CGPoint]
    ) {
        guard depth < 16, distance(control, toSegmentFrom: start, to: end) > tolerance else {
            points.append(end)
            return
        }

        let startControl = midpoint(start, control)
        let controlEnd = midpoint(control, end)
        let split = midpoint(startControl, controlEnd)
        flattenQuadratic(start, startControl, split, tolerance: tolerance, depth: depth + 1, into: &points)
        flattenQuadratic(split, controlEnd, end, tolerance: tolerance, depth: depth + 1, into: &points)
    }

    /// Subdivides a cubic Bézier curve until both control points are within tolerance of its chord.
    private static func flattenCubic(
        _ start: CGPoint,
        _ control1: CGPoint,
        _ control2: CGPoint,
        _ end: CGPoint,
        tolerance: Double,
        depth: Int,
        into points: inout [CGPoint]
    ) {
        let flatness = max(
            distance(control1, toSegmentFrom: start, to: end),
            distance(control2, toSegmentFrom: start, to: end)
        )
        guard depth < 16, flatness > tolerance else {
            points.append(end)
            return
        }

        let startControl1 = midpoint(start, control1)
        let control1Control2 = midpoint(control1, control2)
        let control2End = midpoint(control2, end)
        let splitControl1 = midpoint(startControl1, control1Control2)
        let splitControl2 = midpoint(control1Control2, control2End)
        let split = midpoint(splitControl1, splitControl2)
        flattenCubic(
            start,
            startControl1,
            splitControl1,
            split,
            tolerance: tolerance,
            depth: depth + 1,
            into: &points
        )
        flattenCubic(
            split,
            splitControl2,
            control2End,
            end,
            tolerance: tolerance,
            depth: depth + 1,
            into: &points
        )
    }

    /// Returns the midpoint between two points.
    private static func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
        CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    /// Returns the shortest distance from a point to a finite line segment.
    private static func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > Double.ulpOfOne else {
            let dx = point.x - start.x
            let dy = point.y - start.y
            return (dx * dx + dy * dy).squareRoot()
        }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let parameter = min(1, max(0, projection))
        let distanceX = point.x - (start.x + parameter * dx)
        let distanceY = point.y - (start.y + parameter * dy)
        return (distanceX * distanceX + distanceY * distanceY).squareRoot()
    }
}
