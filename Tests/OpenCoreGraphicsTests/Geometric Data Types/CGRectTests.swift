import Testing
@testable import OpenCoreGraphics

/// Tests rectangle geometry, special values, and containment.
struct CGRectTests {
    /// Verifies rectangle initializers and geometric properties.
    @Test
    func initializersAndBounds() {
        let rect = CGRect(x: 2, y: 3, width: 8, height: 10)

        #expect(CGRect(origin: rect.origin, size: rect.size) == rect)
        #expect(CGRect(x: 2.0, y: 3.0, width: 8.0, height: 10.0) == rect)
        #expect(rect.origin == CGPoint(x: 2, y: 3))
        #expect(rect.size == CGSize(width: 8, height: 10))
        #expect(rect.width == 8)
        #expect(rect.height == 10)
        #expect(rect.minX == 2)
        #expect(rect.minY == 3)
        #expect(rect.maxX == 10)
        #expect(rect.maxY == 13)
        #expect(rect.midX == 6)
        #expect(rect.midY == 8)
    }

    /// Verifies special rectangles and empty/null/infinite checks.
    @Test
    func specialRectangles() {
        #expect(CGRect.zero.isEmpty)
        #expect(CGRect(x: 5, y: 6, width: 0, height: 2).isEmpty)
        #expect(CGRect.infinite.isInfinite)
        #expect(CGRect(x: 0, y: 0, width: .infinity, height: 1).isInfinite)
        #expect(CGRect.null.isNull)
        #expect(CGRect(x: 0, y: 0, width: .nan, height: 1).isNull)
    }

    /// Verifies transformed bounds and point/rectangle containment.
    @Test
    func applyingAndContainment() {
        let rect = CGRect(x: 2, y: 3, width: 8, height: 10)
        let moved = rect.applying(.translate(5, 7))
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)

        #expect(moved == CGRect(x: 7, y: 10, width: 8, height: 10))
        #expect(bounds.contains(CGPoint(x: 20, y: 20)))
        #expect(!bounds.contains(CGPoint(x: 21, y: 20)))
        #expect(bounds.contains(CGRect(x: 3, y: 4, width: 5, height: 6)))
        #expect(!bounds.contains(CGRect(x: 3, y: 4, width: 25, height: 6)))
    }
}
