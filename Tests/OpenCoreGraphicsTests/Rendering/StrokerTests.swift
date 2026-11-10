import Testing
@testable import OpenCoreGraphics

/// Tests stroke outline generation for widths, endpoint caps, joins, and miter limits.
struct StrokerTests {
    /// Verifies butt and square caps produce the expected horizontal rectangles.
    @Test
    func createsButtAndSquareCaps() throws {
        let line = Polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)], isClosed: false)
        let buttOutline = try #require(Stroker.outline([line], style: strokeStyle(cap: .butt)).first)
        let squareOutline = try #require(Stroker.outline([line], style: strokeStyle(cap: .square)).first)

        #expect(buttOutline.isClosed)
        #expect(buttOutline.points == [
            CGPoint(x: 0, y: 2),
            CGPoint(x: 10, y: 2),
            CGPoint(x: 10, y: -2),
            CGPoint(x: 0, y: -2)
        ])
        #expect(squareOutline.points == [
            CGPoint(x: -2, y: 2),
            CGPoint(x: 12, y: 2),
            CGPoint(x: 12, y: -2),
            CGPoint(x: -2, y: -2)
        ])
    }

    /// Verifies miter joins retain the corner until the configured limit requires a bevel.
    @Test
    func respectsMiterLimitAtRightAngle() throws {
        let corner = Polyline(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)],
            isClosed: false
        )
        let miter = try #require(Stroker.outline([corner], style: strokeStyle(miterLimit: 10)).first)
        let bevel = try #require(Stroker.outline([corner], style: strokeStyle(miterLimit: 1)).first)

        #expect(miter.points.contains(CGPoint(x: 12, y: -2)))
        #expect(bevel.points.contains(CGPoint(x: 10, y: -2)))
        #expect(bevel.points.contains(CGPoint(x: 12, y: 0)))
        #expect(bevel.points.contains(CGPoint(x: 12, y: -2)) == false)
    }

    /// Verifies a closed path produces oppositely wound outer and inner contours.
    @Test
    func createsClosedStrokeRing() throws {
        let rectangle = Polyline(
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 0),
                CGPoint(x: 10, y: 10),
                CGPoint(x: 0, y: 10)
            ],
            isClosed: true
        )
        let outlines = Stroker.outline([rectangle], style: strokeStyle())

        #expect(outlines.count == 2)
        #expect(outlines.allSatisfy { $0.isClosed })
        #expect(signedArea(outlines[0].points) * signedArea(outlines[1].points) < 0)
        #expect(outlines[0].points.contains(CGPoint(x: -2, y: -2)))
        #expect(outlines[1].points.contains(CGPoint(x: 2, y: 2)))
    }

    /// Verifies an even dash pattern creates five ten-point segments on a 100-point line.
    @Test
    func appliesDashLengthsAcrossLine() throws {
        let line = Polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], isClosed: false)
        let outlines = Stroker.outline([line], style: strokeStyle(dashLengths: [10, 10]))
        let bounds = try outlines.map { try horizontalBounds(of: $0) }

        #expect(outlines.count == 5)
        #expect(bounds.map(\.minimum) == [0, 20, 40, 60, 80])
        #expect(bounds.map { $0.maximum - $0.minimum } == [10, 10, 10, 10, 10])
    }

    /// Verifies a positive dash phase starts partway through the first painted interval.
    @Test
    func appliesDashPhase() throws {
        let line = Polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], isClosed: false)
        let outlines = Stroker.outline(
            [line],
            style: strokeStyle(dashPhase: 5, dashLengths: [10, 10])
        )
        let bounds = try outlines.map { try horizontalBounds(of: $0) }

        #expect(zip(bounds.map(\.minimum), [0, 15, 35, 55, 75, 95]).allSatisfy {
            abs($0.0 - $0.1) < 1e-9
        })
        #expect(zip(bounds.map { $0.maximum - $0.minimum }, [5, 10, 10, 10, 10, 5]).allSatisfy {
            abs($0.0 - $0.1) < 1e-9
        })
    }

    /// Verifies an empty dash pattern keeps a path continuous.
    @Test
    func emptyDashPatternKeepsContinuousStroke() throws {
        let line = Polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], isClosed: false)
        let outline = try #require(Stroker.outline([line], style: strokeStyle()).first)
        let bounds = try horizontalBounds(of: outline)

        #expect(bounds.minimum == 0)
        #expect(bounds.maximum == 100)
    }

    /// Verifies round caps and joins produce closed outlines.
    @Test
    func createsRoundOutlines() throws {
        let line = Polyline(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)], isClosed: false)
        let outline = try #require(Stroker.outline([line], style: strokeStyle(cap: .round)).first)
        let corner = Polyline(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)],
            isClosed: false
        )
        let roundedJoin = try #require(
            Stroker.outline([corner], style: strokeStyle(cap: .butt, join: .round)).first
        )

        #expect(outline.isClosed)
        #expect(outline.points.count > 4)
        #expect(outline.points.contains { abs($0.x - 12) < 1e-6 })
        #expect(outline.points.contains { abs($0.x + 2) < 1e-6 })
        #expect(roundedJoin.points.count > 6)
    }

    /// Creates a reusable stroke style for outline geometry tests.
    private func strokeStyle(
        cap: CGLineCap = .butt,
        join: CGLineJoin = .miter,
        miterLimit: Double = 10,
        dashPhase: Double = 0,
        dashLengths: [Double] = []
    ) -> StrokeStyle {
        StrokeStyle(
            width: 4,
            cap: cap,
            join: join,
            miterLimit: miterLimit,
            dashPhase: dashPhase,
            dashLengths: dashLengths
        )
    }

    /// Calculates the signed area of a closed polygon without repeating its first point.
    private func signedArea(_ points: [CGPoint]) -> Double {
        points.indices.reduce(0) { area, index in
            let current = points[index]
            let next = points[(index + 1) % points.count]
            return area + current.x * next.y - next.x * current.y
        }
    }

    /// Returns horizontal bounds for an outline's vertices.
    private func horizontalBounds(of polyline: Polyline) throws -> (minimum: Double, maximum: Double) {
        let minimum = try #require(polyline.points.map(\.x).min())
        let maximum = try #require(polyline.points.map(\.x).max())
        return (minimum, maximum)
    }
}
