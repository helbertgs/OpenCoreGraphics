import struct Foundation.Data
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

    /// Verifies a convex quadrilateral remains a direct two-triangle fill.
    @Test
    func triangulatesConvexQuadrilateralWithoutStencil() throws {
        var path = CGPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 8, y: 0))
        path.addLine(to: CGPoint(x: 6, y: 5))
        path.addLine(to: CGPoint(x: 1, y: 7))
        path.closeSubpath()

        let vertices = try #require(GLRendererGeometry.convexPolygonVertices(for: path))

        #expect(vertices.count == 6)
    }

    /// Verifies a self-intersecting star is routed through stencil geometry.
    @Test
    func triangulatesSelfIntersectingStarForStencil() throws {
        let points = [
            CGPoint(x: 100, y: 0),
            CGPoint(x: 200, y: 150),
            CGPoint(x: 160, y: 300),
            CGPoint(x: 40, y: 300),
            CGPoint(x: 0, y: 150)
        ]
        var path = CGPath()
        path.move(to: points[0])
        for index in [2, 4, 1, 3] {
            path.addLine(to: points[index])
        }
        path.closeSubpath()
        let convexVertices = GLRendererGeometry.convexPolygonVertices(for: path)
        let stencilVertices = GLRendererGeometry.stencilVertices(for: path)

        #expect(convexVertices == nil)
        #expect(stencilVertices.count == 9)
    }

    /// Verifies paths with more than sixteen vertices retain every contour point.
    @Test
    func removesTheSixteenVertexLimitForStencilGeometry() throws {
        var points: [CGPoint] = []
        for index in 0..<5 {
            points.append(CGPoint(x: Double(index * 20), y: 0))
        }
        for index in 0..<5 {
            points.append(CGPoint(x: 100, y: Double(index * 20)))
        }
        for index in 0..<5 {
            points.append(CGPoint(x: Double(100 - index * 20), y: 100))
        }
        for index in 0..<5 {
            points.append(CGPoint(x: 0, y: Double(100 - index * 20)))
        }
        var path = CGPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        let stencilVertices = GLRendererGeometry.stencilVertices(for: path)

        #expect(GLRendererGeometry.convexPolygonVertices(for: path) == nil)
        #expect(stencilVertices.count == 54)
    }

    /// Verifies a requested line width expands a rectangle into both outline contours.
    @Test
    func expandsStrokePathIntoFilledOutlineGeometry() throws {
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let style = StrokeStyle(width: 8, cap: .butt, join: .miter, miterLimit: 10)
        let vertices = GLRendererGeometry.strokeVertices(for: path, style: style)
        let points = vertices.map { CGPoint(x: Double($0.positionX), y: Double($0.positionY)) }
        let minimumX = try #require(points.map(\.x).min())
        let maximumX = try #require(points.map(\.x).max())
        let minimumY = try #require(points.map(\.y).min())
        let maximumY = try #require(points.map(\.y).max())

        #expect(vertices.count == 12)
        #expect(minimumX == -4)
        #expect(maximumX == 14)
        #expect(minimumY == -4)
        #expect(maximumY == 14)
    }

    /// Verifies image vertices preserve the transformed quad and correct top-down pixel orientation.
    @Test
    func mapsImagePixelsToDestinationQuad() throws {
        let destination = [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 138, y: 20),
            CGPoint(x: 138, y: 148),
            CGPoint(x: 10, y: 148)
        ]
        let vertices = try #require(
            GLRendererGeometry.imageVertices(
                for: destination,
                imageSize: CGSize(width: 64, height: 64),
                byTiling: false
            )
        )

        #expect(vertices.map { CGPoint(x: Double($0.positionX), y: Double($0.positionY)) } == [
            destination[0], destination[1], destination[2],
            destination[0], destination[2], destination[3]
        ])
        #expect(vertices.map { CGPoint(x: Double($0.textureX), y: Double($0.textureY)) } == [
            CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0),
            CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)
        ])
    }

    /// Verifies tiling repeats at the source image's pixel dimensions.
    @Test
    func repeatsImageTextureCoordinatesWhenTiling() throws {
        let destination = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 128, y: 0),
            CGPoint(x: 128, y: 64),
            CGPoint(x: 0, y: 64)
        ]
        let vertices = try #require(
            GLRendererGeometry.imageVertices(
                for: destination,
                imageSize: CGSize(width: 64, height: 64),
                byTiling: true
            )
        )

        #expect(vertices.map(\.textureX) == [0, 2, 2, 0, 2, 0])
        #expect(vertices.map(\.textureY) == [1, 1, 0, 1, 0, 0])
    }

    /// Verifies glyph quads preserve baseline, character spacing, and flipped atlas coordinates.
    @Test
    func mapsGlyphBitmapsToTransformedAtlasQuads() throws {
        let bitmap = CGGlyphBitmap(
            width: 2,
            height: 3,
            xOffset: 1,
            yOffset: 2,
            coverage: Data([0, 64, 128, 192, 224, 255])
        )
        let atlas = try #require(CGGlyphAtlas(bitmaps: [bitmap, bitmap]))
        let vertices = GLRendererGeometry.glyphVertices(
            [1, 2],
            positions: [CGPoint(x: 3, y: 20), CGPoint(x: 10, y: 30)],
            glyphAtlas: atlas,
            characterSpacing: 2,
            textMatrix: .identity,
            textPosition: .zero,
            ctm: .identity
        )

        #expect(vertices.count == 12)
        #expect(vertices.map { CGPoint(x: Double($0.positionX), y: Double($0.positionY)) } == [
            CGPoint(x: 4, y: 15),
            CGPoint(x: 6, y: 15),
            CGPoint(x: 6, y: 18),
            CGPoint(x: 4, y: 15),
            CGPoint(x: 6, y: 18),
            CGPoint(x: 4, y: 18),
            CGPoint(x: 13, y: 25),
            CGPoint(x: 15, y: 25),
            CGPoint(x: 15, y: 28),
            CGPoint(x: 13, y: 25),
            CGPoint(x: 15, y: 28),
            CGPoint(x: 13, y: 28)
        ])
        #expect(abs(Double(vertices[0].textureX) - 1.0 / 9) < 0.000001)
        #expect(abs(Double(vertices[0].textureY) - 4.0 / 5) < 0.000001)
        #expect(abs(Double(vertices[2].textureX) - 3.0 / 9) < 0.000001)
        #expect(abs(Double(vertices[2].textureY) - 1.0 / 5) < 0.000001)

        let transformed = GLRendererGeometry.glyphVertices(
            [1],
            positions: [CGPoint(x: 3, y: 20)],
            glyphAtlas: try #require(CGGlyphAtlas(bitmaps: [bitmap])),
            characterSpacing: 0,
            textMatrix: CGAffineTransform(a: 2, b: 0, c: 0, d: 3, tx: 1, ty: 4),
            textPosition: CGPoint(x: 5, y: 6),
            ctm: CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 7, ty: 8)
        )
        #expect(CGPoint(x: Double(transformed[0].positionX), y: Double(transformed[0].positionY)) == CGPoint(x: 21, y: 63))
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
            ) == [0.04, 0.08, 0.12, 0.4]
        )
        #expect(
            GLRendererGeometry.rgbaComponents(for: CGColor(gray: 0.5, alpha: 0.6))
                == [0.3, 0.3, 0.3, 0.6]
        )
        #expect(
            GLRendererGeometry.rgbaComponents(
                for: CGColor(cyan: 0, magenta: 0, yellow: 0, black: 0, alpha: 1)
            ) == [1, 1, 1, 1]
        )
    }

    /// Verifies OpenGL color uniforms receive linearized sRGB values before premultiplication.
    @Test
    func convertsSRGBColorToLinearShaderComponents() throws {
        let components = try #require(
            GLRendererGeometry.rgbaComponents(
                for: CGColor(sred: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
            )
        )

        #expect(abs(Double(components[0]) - 0.1070) < 0.001)
        #expect(abs(Double(components[1]) - 0.1070) < 0.001)
        #expect(abs(Double(components[2]) - 0.1070) < 0.001)
        #expect(components[3] == 0.5)
    }
}
