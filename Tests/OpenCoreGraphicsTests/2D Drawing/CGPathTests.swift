import Darwin
import Testing
@testable import OpenCoreGraphics

struct CGPathTests {
    @Test func initEmptyPath() {
        let path = CGPath()
        #expect(path.isEmpty)
        #expect(path.subpath.count == 0)
    }

    @Test func initRect() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 20)
        let path = CGPath(rect: rect)
        #expect(!path.isEmpty)
        #expect(path.subpath.count == 1)
    }

    @Test func initEllipse() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let path = CGPath(ellipseIn: rect)
        #expect(!path.isEmpty)
        #expect(path.subpath.count > 0)
    }

    @Test func initRoundedRect() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2)
        #expect(!path.isEmpty)
        #expect(path.subpath.count > 0)
    }

    @Test func moveToAndAddLine() {
        var path = CGPath()
        path.move(to: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: 2, y: 2))
        #expect(path.subpath.count == 2)
        #expect(path.currentPoint == CGPoint(x: 2, y: 2))
    }

    @Test func addLinesBetween() {
        var path = CGPath()
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)]
        path.addLines(between: points)

        #expect(path.subpath.map(\.type) == [.moveToPoint, .addLineToPoint, .addLineToPoint])
        #expect(path.subpath.first?.points == [points[0]])
        #expect(path.currentPoint == points.last)
    }

    /// Verifies an empty sequence does not change the path.
    @Test
    func addLinesBetweenEmptyPointsDoesNotChangePath() {
        var path = CGPath()
        path.move(to: CGPoint(x: 4, y: 5))
        let originalPath = path

        path.addLines(between: [])

        #expect(path == originalPath)
    }

    @Test func addRect() {
        var path = CGPath()
        let rect = CGRect(x: 0, y: 0, width: 5, height: 5)
        path.addRect(rect)
        #expect(path.subpath.count == 1)
    }

    @Test func addRects() {
        var path = CGPath()
        let rects = [CGRect(x: 0, y: 0, width: 2, height: 2), CGRect(x: 2, y: 2, width: 2, height: 2)]
        path.addRects(rects)
        #expect(path.subpath.count == 2)
    }

    @Test func addEllipse() {
        var path = CGPath()
        let rect = CGRect(x: 0, y: 0, width: 10, height: 5)
        path.addEllipse(in: rect)
        #expect(path.subpath.count > 0)
    }

    @Test func addRoundedRect() {
        var path = CGPath()
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        path.addRoundedRect(in: rect, cornerWidth: 2, cornerHeight: 2)
        #expect(path.subpath.count > 0)
    }

    /// Verifies a quarter-circle uses a cubic curve and remains close to the circle.
    @Test
    func addArc() throws {
        var path = CGPath()
        path.addArc(center: .zero, radius: 10, startAngle: 0, endAngle: .pi / 2, clockwise: false)

        #expect(path.subpath.map(\.type) == [.moveToPoint, .addCurveToPoint])
        #expect(abs(path.currentPoint.x) < 1e-6)
        #expect(abs(path.currentPoint.y - 10) < 1e-6)
        let curve = try #require(path.subpath.last?.points)
        let midpoint = CGPoint(
            x: (curve[0].x + 3 * curve[1].x + 3 * curve[2].x + curve[3].x) / 8,
            y: (curve[0].y + 3 * curve[1].y + 3 * curve[2].y + curve[3].y) / 8
        )
        #expect(abs(hypot(midpoint.x, midpoint.y) - 10) < 0.01)
    }

    /// Verifies clockwise and counterclockwise arcs follow their requested direction.
    @Test
    func addArcRespectsClockwiseDirection() {
        var counterclockwisePath = CGPath()
        counterclockwisePath.addArc(
            center: .zero,
            radius: 10,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: false
        )
        var clockwisePath = CGPath()
        clockwisePath.addArc(
            center: .zero,
            radius: 10,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true
        )

        #expect(counterclockwisePath.subpath.filter { $0.type == .addCurveToPoint }.count == 1)
        #expect(clockwisePath.subpath.filter { $0.type == .addCurveToPoint }.count == 3)
        #expect(abs(clockwisePath.currentPoint.x) < 1e-6)
        #expect(abs(clockwisePath.currentPoint.y - 10) < 1e-6)
    }

    /// Verifies an arc added to an existing subpath connects with a line to its start.
    @Test
    func addArcConnectsToExistingSubpath() {
        var path = CGPath()
        path.move(to: CGPoint(x: -5, y: 0))
        path.addArc(center: .zero, radius: 10, startAngle: 0, endAngle: .pi / 2, clockwise: false)

        #expect(path.subpath.map(\.type) == [.moveToPoint, .addLineToPoint, .addCurveToPoint])
        #expect(path.subpath[1].points.last == CGPoint(x: 10, y: 0))
    }

    /// Verifies tangent arcs connect to the first tangent point and end at the second.
    @Test
    func addArcTangent() throws {
        var path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addArc(tangent1End: CGPoint(x: 10, y: 0), tangent2End: CGPoint(x: 10, y: 10), radius: 5)

        #expect(path.subpath.map(\.type) == [.moveToPoint, .addLineToPoint, .addCurveToPoint])
        #expect(abs(path.currentPoint.x - 10) < 1e-6)
        #expect(abs(path.currentPoint.y - 5) < 1e-6)
        let curveStart = try #require(path.subpath.last?.points.first)
        #expect(abs(curveStart.x - 5) < 1e-6)
        #expect(abs(curveStart.y) < 1e-6)
    }

    @Test func addRelativeArc() {
        var path = CGPath()
        path.addRelativeArc(center: CGPoint(x: 0, y: 0), radius: 5, startAngle: 0, delta: .pi / 2)
        #expect(abs(path.currentPoint.x) < 1e-6)
        #expect(abs(path.currentPoint.y - 5) < 1e-6)
    }

    @Test func addCurve() {
        var path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 3, y: 3), control1: CGPoint(x: 1, y: 2), control2: CGPoint(x: 2, y: 1))
        #expect(path.currentPoint == CGPoint(x: 3, y: 3))
    }

    @Test func addQuadCurve() {
        var path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: 2, y: 2), control: CGPoint(x: 1, y: 3))
        #expect(path.currentPoint == CGPoint(x: 2, y: 2))
    }

    @Test func addPath() {
        var path1 = CGPath()
        path1.move(to: CGPoint(x: 0, y: 0))
        path1.addLine(to: CGPoint(x: 1, y: 1))
        var path2 = CGPath()
        path2.addPath(path1)
        #expect(path2.subpath.count == path1.subpath.count)
        #expect(path2.currentPoint == path1.currentPoint)
    }

    @Test func closeSubpath() {
        var path = CGPath()
        let startingPoint = CGPoint(x: 4, y: 5)
        path.move(to: startingPoint)
        path.addLine(to: CGPoint(x: 1, y: 1))
        path.closeSubpath()
        #expect(path.subpath.last?.type == .closeSubpath)
        #expect(path.currentPoint == startingPoint)
    }

    /// Verifies closing an empty path is a no-op.
    @Test
    func closeEmptySubpathDoesNotChangePath() {
        var path = CGPath()

        path.closeSubpath()

        #expect(path.isEmpty)
        #expect(path.currentPoint == .zero)
        #expect(path.boundingBox.isNull)
        #expect(path.boundingBoxOfPath.isNull)
    }

    /// Verifies closing a subpath that is already closed is a no-op.
    @Test
    func closeAlreadyClosedSubpathDoesNotChangePath() {
        var path = CGPath()
        path.move(to: CGPoint(x: 2, y: 3))
        path.addLine(to: CGPoint(x: 5, y: 7))
        path.closeSubpath()
        let closedPath = path

        path.closeSubpath()

        #expect(path == closedPath)
    }

    /// Verifies bounds distinguish Bézier control points from points on the curves.
    @Test
    func calculatesControlPointAndPathBounds() {
        var path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 10))

        #expect(path.boundingBox == CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(path.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 5))

        path.addLine(to: CGPoint(x: 12, y: 3))
        #expect(path.boundingBox == CGRect(x: 0, y: 0, width: 12, height: 10))
        #expect(path.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 12, height: 5))
    }

    /// Verifies a cubic curve's geometric bounds exclude its control points.
    @Test
    func calculatesCubicCurveBounds() {
        var path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(
            to: CGPoint(x: 10, y: 0),
            control1: CGPoint(x: 0, y: 10),
            control2: CGPoint(x: 10, y: 10)
        )

        #expect(path.boundingBox == CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(path.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 7.5))
    }

    /// Verifies empty paths expose null bounds and copies preserve or transform geometry.
    @Test
    func copiesPathWithAndWithoutTransform() throws {
        let emptyPath = CGPath()
        #expect(emptyPath.boundingBox.isNull)
        #expect(emptyPath.boundingBoxOfPath.isNull)
        #expect(emptyPath == CGPath())
        #expect(Set([emptyPath, CGPath()]).count == 1)

        let path = CGPath(rect: CGRect(x: 1, y: 2, width: 3, height: 4))
        let copy = try #require(path.copy())
        let transformedCopy = try #require(path.copy(using: .translate(5, 7)))

        #expect(copy == path)
        #expect(transformedCopy.boundingBox == CGRect(x: 6, y: 9, width: 3, height: 4))
        #expect(transformedCopy.currentPoint == CGPoint(x: 6, y: 9))
    }

    /// Verifies rectangle containment and the effect of the point transform.
    @Test
    func containsPointsInsideAndOutsideRectangle() {
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10))

        #expect(path.contains(CGPoint(x: 5, y: 5)))
        #expect(!path.contains(CGPoint(x: 15, y: 5)))
        #expect(path.contains(CGPoint(x: 3, y: 4), transform: .translate(2, 1)))
    }

    /// Verifies winding and even-odd rules differ in the center of a five-point star.
    @Test
    func fillRulesDifferInFivePointStarCenter() {
        let starPoints = [
            CGPoint(x: 0, y: -10),
            CGPoint(x: 5.87785, y: 8.09017),
            CGPoint(x: -9.510565, y: -3.09017),
            CGPoint(x: 9.510565, y: -3.09017),
            CGPoint(x: -5.87785, y: 8.09017)
        ]
        var path = CGPath()
        path.move(to: starPoints[0])
        starPoints.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()

        #expect(path.contains(.zero, using: .winding))
        #expect(!path.contains(.zero, using: .evenOdd))
    }

    @Test func isEmpty() {
        var path = CGPath()
        #expect(path.isEmpty)
        path.move(to: CGPoint(x: 0, y: 0))
        #expect(!path.isEmpty)
    }

    @Test func containsAlwaysFalse() {
        let path = CGPath()
        #expect(!path.contains(CGPoint(x: 0, y: 0)))
    }
}
