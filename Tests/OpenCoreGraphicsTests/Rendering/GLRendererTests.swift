import Testing
@testable import OpenCoreGraphics

/// Tests the geometry and projection calculations used by the OpenGL renderer.
struct GLRendererTests {
    /// Verifies a rectangle is triangulated into two ordered triangles.
    @Test
    func rectangleBecomesTwoTriangles() throws {
        let path = CGPath(rect: CGRect(x: 2, y: 3, width: 8, height: 10))
        let vertices = try #require(GLRendererGeometry.rectangleVertices(for: path))

        #expect(vertices.map { CGPoint(x: Double($0.positionX), y: Double($0.positionY)) } == [
            CGPoint(x: 2, y: 3),
            CGPoint(x: 10, y: 3),
            CGPoint(x: 10, y: 13),
            CGPoint(x: 2, y: 3),
            CGPoint(x: 10, y: 13),
            CGPoint(x: 2, y: 13)
        ])
        #expect(vertices.allSatisfy { $0.textureX == 0 && $0.textureY == 0 })
    }

    /// Verifies non-rectangular path elements are not sent to rectangle triangulation.
    @Test
    func rejectsNonRectangularPaths() {
        var path = CGPath(rect: CGRect(x: 0, y: 0, width: 4, height: 5))
        path.addLine(to: CGPoint(x: 8, y: 9))

        #expect(GLRendererGeometry.rectangleVertices(for: path) == nil)
    }

    /// Verifies pixel coordinates map to the expected column-major clip matrix.
    @Test
    func buildsPixelSpaceOrthographicProjection() throws {
        let projection = try #require(
            GLRendererGeometry.orthographicProjection(for: CGSize(width: 200, height: 100))
        )

        #expect(projection == [
            0.01, 0, 0, 0,
            0, 0.02, 0, 0,
            0, 0, -1, 0,
            -1, -1, 0, 1
        ])
        #expect(GLRendererGeometry.orthographicProjection(for: .zero) == nil)
    }

    /// Verifies RGB, gray, and CMYK colors produce shader-compatible RGBA values.
    @Test
    func convertsSupportedColorSpacesToRGBA() {
        #expect(
            GLRendererGeometry.rgbaComponents(
                for: CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
            ) == [0.1, 0.2, 0.3, 0.4]
        )
        #expect(
            GLRendererGeometry.rgbaComponents(for: CGColor(gray: 0.5, alpha: 0.6))
                == [0.5, 0.5, 0.5, 0.6]
        )
        #expect(
            GLRendererGeometry.rgbaComponents(
                for: CGColor(cyan: 0, magenta: 0, yellow: 0, black: 0, alpha: 1)
            ) == [1, 1, 1, 1]
        )
    }
}
