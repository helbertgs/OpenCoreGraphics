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
        let path = CGPath()
        path.move(to: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: 2, y: 2))
        #expect(path.subpath.count == 2)
        #expect(path.currentPoint == CGPoint(x: 2, y: 2))
    }

    @Test func addLinesBetween() {
        let path = CGPath()
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)]
        path.move(to: points[0])
        path.addLines(between: points)
        #expect(path.currentPoint == points.last)
    }

    @Test func addRect() {
        let path = CGPath()
        let rect = CGRect(x: 0, y: 0, width: 5, height: 5)
        path.addRect(rect)
        #expect(path.subpath.count == 1)
    }

    @Test func addRects() {
        let path = CGPath()
        let rects = [CGRect(x: 0, y: 0, width: 2, height: 2), CGRect(x: 2, y: 2, width: 2, height: 2)]
        path.addRects(rects)
        #expect(path.subpath.count == 2)
    }

    @Test func addEllipse() {
        let path = CGPath()
        let rect = CGRect(x: 0, y: 0, width: 10, height: 5)
        path.addEllipse(in: rect)
        #expect(path.subpath.count > 0)
    }

    @Test func addRoundedRect() {
        let path = CGPath()
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        path.addRoundedRect(in: rect, cornerWidth: 2, cornerHeight: 2)
        #expect(path.subpath.count > 0)
    }

    @Test func addArc() {
        let path = CGPath()
        path.addArc(center: CGPoint(x: 0, y: 0), radius: 5, startAngle: 0, endAngle: .pi, clockwise: false)
        #expect(path.subpath.count > 0)
    }

    @Test func addArcTangent() {
        let path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addArc(tangent1End: CGPoint(x: 1, y: 0), tangent2End: CGPoint(x: 1, y: 1), radius: 1)
        #expect(path.subpath.count > 1)
    }

    @Test func addRelativeArc() {
        let path = CGPath()
        path.addRelativeArc(center: CGPoint(x: 0, y: 0), radius: 5, startAngle: 0, delta: .pi / 2)
        #expect(path.subpath.count > 0)
    }

    @Test func addCurve() {
        let path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 3, y: 3), control1: CGPoint(x: 1, y: 2), control2: CGPoint(x: 2, y: 1))
        #expect(path.currentPoint == CGPoint(x: 3, y: 3))
    }

    @Test func addQuadCurve() {
        let path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: 2, y: 2), control: CGPoint(x: 1, y: 3))
        #expect(path.currentPoint == CGPoint(x: 2, y: 2))
    }

    @Test func addPath() {
        let path1 = CGPath()
        path1.move(to: CGPoint(x: 0, y: 0))
        path1.addLine(to: CGPoint(x: 1, y: 1))
        let path2 = CGPath()
        path2.addPath(path1)
        #expect(path2.subpath.count == path1.subpath.count)
        #expect(path2.currentPoint == path1.currentPoint)
    }

    @Test func closeSubpath() {
        let path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 1, y: 1))
        path.closeSubpath()
        #expect(path.subpath.last?.type == .closeSubpath)
        #expect(path.currentPoint == .zero)
    }

    @Test func isEmpty() {
        let path = CGPath()
        #expect(path.isEmpty)
        path.move(to: CGPoint(x: 0, y: 0))
        #expect(!path.isEmpty)
    }

    @Test func containsAlwaysFalse() {
        let path = CGPath()
        #expect(!path.contains(CGPoint(x: 0, y: 0)))
    }
}
