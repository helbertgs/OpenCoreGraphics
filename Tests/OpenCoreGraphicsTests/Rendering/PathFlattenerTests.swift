import Testing
@testable import OpenCoreGraphics

/// Tests conversion of path subpaths and curves into tolerance-controlled polylines.
struct PathFlattenerTests {
    /// Verifies a circular path stays within the requested radial tolerance.
    @Test
    func flattensCircleWithinDefaultTolerance() throws {
        let path = CGPath(ellipseIn: CGRect(x: -100, y: -100, width: 200, height: 200))
        let polylines = PathFlattener.flatten(path)
        let polyline = try #require(polylines.first)

        #expect(polylines.count == 1)
        #expect(polyline.isClosed)
        #expect(polyline.points.allSatisfy { abs(($0.x * $0.x + $0.y * $0.y).squareRoot() - 100) <= 0.25 })
    }

    /// Verifies a line remains represented by only its start and end points.
    @Test
    func flattensLineToTwoPoints() throws {
        var path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 10, y: 0))
        let polyline = try #require(PathFlattener.flatten(path).first)

        #expect(polyline.points == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)])
        #expect(polyline.isClosed == false)
    }

    /// Verifies a quadratic curve is subdivided into points on the curve.
    @Test
    func flattensQuadraticCurveAdaptively() throws {
        var path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 10))
        let polyline = try #require(PathFlattener.flatten(path).first)

        #expect(polyline.points.count > 2)
        #expect(polyline.points.first == CGPoint(x: 0, y: 0))
        #expect(polyline.points.last == CGPoint(x: 10, y: 0))
        let maximumY = try #require(polyline.points.map(\.y).max())
        #expect(abs(maximumY - 5) < 0.25)
    }

    /// Verifies closed and open subpaths remain separate and retain their closure state.
    @Test
    func preservesMultipleSubpathsAndClosure() {
        var path = CGPath()
        path.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
        path.move(to: CGPoint(x: 20, y: 20))
        path.addLine(to: CGPoint(x: 30, y: 30))

        let polylines = PathFlattener.flatten(path)

        #expect(polylines.count == 2)
        #expect(polylines[0].isClosed)
        #expect(polylines[0].points.count == 4)
        #expect(polylines[1].isClosed == false)
        #expect(polylines[1].points == [CGPoint(x: 20, y: 20), CGPoint(x: 30, y: 30)])
    }
}
