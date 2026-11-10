import Foundation

/// Expands flattened paths into closed polygons that represent their strokes.
enum Stroker {
    /// Generates fillable stroke outlines for the supplied polylines.
    /// - Parameters:
    ///   - polylines: The flattened path subpaths to stroke.
    ///   - style: The line width, endpoint caps, joins, and miter limit.
    /// - Returns: Closed polygons that cover the requested stroke geometry.
    /// - Precondition: The line width is finite and nonnegative.
    static func outline(_ polylines: [Polyline], style: StrokeStyle) -> [Polyline] {
        precondition(style.width.isFinite && style.width >= 0, "Stroke width must be finite and nonnegative.")
        guard style.width > 0 else { return [] }

        var outlines: [Polyline] = []
        for polyline in polylines {
            let points = cleanedPoints(polyline.points, isClosed: polyline.isClosed)
            guard points.isEmpty == false else { continue }
            if points.count == 1 {
                if let outline = outline(forPoint: points[0], style: style) {
                    outlines.append(outline)
                }
                continue
            }
            if polyline.isClosed, points.count > 2 {
                outlines.append(contentsOf: outline(forClosedPoints: points, style: style))
                continue
            }
            outlines.append(outline(forOpenPoints: points, style: style))
        }
        return outlines
    }

    /// Removes adjacent duplicate points and the repeated endpoint of a closed polyline.
    private static func cleanedPoints(_ points: [CGPoint], isClosed: Bool) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points where result.last != point {
            result.append(point)
        }
        if isClosed, result.count > 1, result.first == result.last {
            result.removeLast()
        }
        return result
    }

    /// Builds the polygon for an open polyline with endpoint caps.
    private static func outline(forOpenPoints points: [CGPoint], style: StrokeStyle) -> Polyline {
        let halfWidth = style.width / 2
        let directions = segmentDirections(for: points)
        let left = offsetPoints(for: points, directions: directions, side: 1, isClosed: false, style: style)
        let right = offsetPoints(for: points, directions: directions, side: -1, isClosed: false, style: style)
        var leftSide = left
        var rightSide = right

        if style.cap == .square, let firstDirection = directions.first, let lastDirection = directions.last {
            leftSide[0] = translated(leftSide[0], by: scaled(firstDirection, by: -halfWidth))
            rightSide[0] = translated(rightSide[0], by: scaled(firstDirection, by: -halfWidth))
            leftSide[leftSide.count - 1] = translated(
                leftSide[leftSide.count - 1],
                by: scaled(lastDirection, by: halfWidth)
            )
            rightSide[rightSide.count - 1] = translated(
                rightSide[rightSide.count - 1],
                by: scaled(lastDirection, by: halfWidth)
            )
        }

        var outline = leftSide
        if style.cap == .round, let firstDirection = directions.first, let lastDirection = directions.last {
            let endNormal = normal(to: lastDirection)
            outline.append(contentsOf: arcPoints(
                center: points[points.count - 1],
                startOffset: scaled(endNormal, by: halfWidth),
                sweep: -.pi
            ).dropFirst())
            outline.append(contentsOf: rightSide.reversed().dropFirst())
            outline.append(contentsOf: arcPoints(
                center: points[0],
                startOffset: scaled(normal(to: firstDirection), by: -halfWidth),
                sweep: -.pi
            ).dropFirst())
        } else {
            outline.append(contentsOf: rightSide.reversed())
        }
        return Polyline(points: outline, isClosed: true)
    }

    /// Builds a polygon for a single point with a round or square cap.
    private static func outline(forPoint point: CGPoint, style: StrokeStyle) -> Polyline? {
        let radius = style.width / 2
        switch style.cap {
        case .butt:
            return nil
        case .square:
            return Polyline(points: [
                CGPoint(x: point.x - radius, y: point.y - radius),
                CGPoint(x: point.x + radius, y: point.y - radius),
                CGPoint(x: point.x + radius, y: point.y + radius),
                CGPoint(x: point.x - radius, y: point.y + radius)
            ], isClosed: true)
        case .round:
            return Polyline(
                points: arcPoints(
                    center: point,
                    startOffset: CGPoint(x: radius, y: 0),
                    sweep: 2 * Double.pi
                ),
                isClosed: true
            )
        }
    }

    /// Builds a closed outline by joining the left and right offset sides.
    private static func outline(forClosedPoints points: [CGPoint], style: StrokeStyle) -> [Polyline] {
        let directions = segmentDirections(for: points, isClosed: true)
        let left = offsetPoints(for: points, directions: directions, side: 1, isClosed: true, style: style)
        let right = offsetPoints(for: points, directions: directions, side: -1, isClosed: true, style: style)
        let signedArea = points.indices.reduce(0.0) { area, index in
            let current = points[index]
            let next = points[(index + 1) % points.count]
            return area + current.x * next.y - next.x * current.y
        }
        let outer = signedArea >= 0 ? right : left
        let inner = signedArea >= 0 ? left : right
        return [
            Polyline(points: outer, isClosed: true),
            Polyline(points: inner.reversed(), isClosed: true)
        ]
    }

    /// Calculates normalized directions for every open or closed polyline segment.
    private static func segmentDirections(for points: [CGPoint], isClosed: Bool = false) -> [CGPoint] {
        let segmentCount = isClosed ? points.count : points.count - 1
        return (0..<segmentCount).map { index in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
            let length = (delta.x * delta.x + delta.y * delta.y).squareRoot()
            return length > Double.ulpOfOne ? CGPoint(x: delta.x / length, y: delta.y / length) : .zero
        }
    }

    /// Calculates one side of the stroke around a polyline.
    private static func offsetPoints(
        for points: [CGPoint],
        directions: [CGPoint],
        side: Double,
        isClosed: Bool,
        style: StrokeStyle
    ) -> [CGPoint] {
        let halfWidth = style.width / 2
        return points.indices.flatMap { index in
            if isClosed == false, index == 0 {
                return [translated(points[index], by: scaled(normal(to: directions[0]), by: side * halfWidth))]
            }
            if isClosed == false, index == points.count - 1 {
                return [translated(
                    points[index],
                    by: scaled(normal(to: directions[directions.count - 1]), by: side * halfWidth)
                )]
            }

            let previousDirection = directions[(index - 1 + directions.count) % directions.count]
            let nextDirection = directions[index % directions.count]
            return joinPoints(
                at: points[index],
                previousDirection: previousDirection,
                nextDirection: nextDirection,
                side: side,
                style: style
            )
        }
    }

    /// Returns the offset points that implement a join at one path vertex.
    private static func joinPoints(
        at vertex: CGPoint,
        previousDirection: CGPoint,
        nextDirection: CGPoint,
        side: Double,
        style: StrokeStyle
    ) -> [CGPoint] {
        let halfWidth = style.width / 2
        let previousNormal = normal(to: previousDirection)
        let nextNormal = normal(to: nextDirection)
        let turn = cross(previousDirection, nextDirection)
        let normalDot = previousNormal.x * nextNormal.x + previousNormal.y * nextNormal.y
        let denominator = 1 + normalDot
        guard abs(denominator) > 1e-10 else {
            return [
                translated(vertex, by: scaled(previousNormal, by: side * halfWidth)),
                translated(vertex, by: scaled(nextNormal, by: side * halfWidth))
            ]
        }

        let miterOffset = scaled(
            CGPoint(
                x: previousNormal.x + nextNormal.x,
                y: previousNormal.y + nextNormal.y
            ),
            by: side * halfWidth / denominator
        )
        let miterPoint = translated(vertex, by: miterOffset)
        let previousOffset = translated(vertex, by: scaled(previousNormal, by: side * halfWidth))
        let nextOffset = translated(vertex, by: scaled(nextNormal, by: side * halfWidth))
        guard abs(turn) > 1e-10 else { return [miterPoint] }
        if turn * side > 0 { return [miterPoint] }

        switch style.join {
        case .miter:
            let ratio = (miterOffset.x * miterOffset.x + miterOffset.y * miterOffset.y).squareRoot() / halfWidth
            return ratio <= style.miterLimit ? [miterPoint] : [previousOffset, nextOffset]
        case .bevel:
            return [previousOffset, nextOffset]
        case .round:
            return arcPoints(
                center: vertex,
                startOffset: scaled(previousNormal, by: side * halfWidth),
                sweep: atan2(turn, previousDirection.x * nextDirection.x + previousDirection.y * nextDirection.y)
            )
        }
    }

    /// Samples a circular arc at 15-degree intervals, including both endpoints.
    private static func arcPoints(center: CGPoint, startOffset: CGPoint, sweep: Double) -> [CGPoint] {
        let radius = (startOffset.x * startOffset.x + startOffset.y * startOffset.y).squareRoot()
        guard radius > 0 else { return [center] }
        let startAngle = atan2(startOffset.y, startOffset.x)
        let segments = max(1, Int(ceil(abs(sweep) / (.pi / 12))))
        return (0...segments).map { step in
            let angle = startAngle + sweep * Double(step) / Double(segments)
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    /// Returns the left-facing unit normal of a direction vector.
    private static func normal(to direction: CGPoint) -> CGPoint {
        CGPoint(x: -direction.y, y: direction.x)
    }

    /// Returns the two-dimensional cross product of two vectors.
    private static func cross(_ first: CGPoint, _ second: CGPoint) -> Double {
        first.x * second.y - first.y * second.x
    }

    /// Scales a vector by a scalar.
    private static func scaled(_ vector: CGPoint, by factor: Double) -> CGPoint {
        CGPoint(x: vector.x * factor, y: vector.y * factor)
    }

    /// Translates a point by a vector.
    private static func translated(_ point: CGPoint, by vector: CGPoint) -> CGPoint {
        CGPoint(x: point.x + vector.x, y: point.y + vector.y)
    }
}
