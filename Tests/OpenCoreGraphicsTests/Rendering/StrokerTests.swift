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
        miterLimit: Double = 10
    ) -> StrokeStyle {
        StrokeStyle(width: 4, cap: cap, join: join, miterLimit: miterLimit, dash: [])
    }

    /// Calculates the signed area of a closed polygon without repeating its first point.
    private func signedArea(_ points: [CGPoint]) -> Double {
        points.indices.reduce(0) { area, index in
            let current = points[index]
            let next = points[(index + 1) % points.count]
            return area + current.x * next.y - next.x * current.y
        }
    }
}
