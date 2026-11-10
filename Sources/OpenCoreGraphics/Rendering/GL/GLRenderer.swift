@preconcurrency import OpenGLAD

/// Converts paths and destination dimensions into OpenGL geometry.
enum GLRendererGeometry {
    /// Triangulates each rectangular subpath into two triangles.
    /// - Parameter path: A path containing only rectangular subpaths.
    /// - Returns: Six vertices per rectangle, or nil when any element is not a rectangle.
    static func rectangleVertices(for path: CGPath) -> [GLBatchVertex]? {
        let elements = path.subpath
        guard elements.isEmpty == false else { return nil }
        var geometryVertices: [GLBatchVertex] = []
        var index = 0

        while index < elements.count {
            let element = elements[index]
            if element.type == .addRectToPoint {
                guard let rectangleVertices = vertices(for: element.points) else { return nil }
                geometryVertices.append(contentsOf: rectangleVertices)
                index += 1
                continue
            }

            guard index + 4 < elements.count,
                  element.type == .moveToPoint,
                  element.points.count == 1,
                  elements[index + 1].type == .addLineToPoint,
                  elements[index + 1].points.count == 2,
                  elements[index + 2].type == .addLineToPoint,
                  elements[index + 2].points.count == 2,
                  elements[index + 3].type == .addLineToPoint,
                  elements[index + 3].points.count == 2,
                  elements[index + 4].type == .closeSubpath,
                  elements[index + 1].points[0] == element.points[0],
                  elements[index + 2].points[0] == elements[index + 1].points[1],
                  elements[index + 3].points[0] == elements[index + 2].points[1],
                  let rectangleVertices = vertices(for: [
                    element.points[0],
                    elements[index + 1].points[1],
                    elements[index + 2].points[1],
                    elements[index + 3].points[1]
                  ]) else {
                return nil
            }

            geometryVertices.append(contentsOf: rectangleVertices)
            index += 5
        }

        return geometryVertices
    }

    /// Triangulates one convex path subpath as a triangle fan.
    /// - Parameter path: A path containing one convex polygon.
    /// - Returns: The polygon's triangle vertices, or nil when the path is not a single convex polygon.
    static func convexPolygonVertices(for path: CGPath) -> [GLBatchVertex]? {
        convexPolygonVertices(for: PathFlattener.flatten(path))
    }

    /// Triangulates one convex flattened subpath as a triangle fan.
    /// - Parameter polylines: The flattened path subpaths.
    /// - Returns: The polygon's triangle vertices, or nil when the path is not one convex polygon.
    static func convexPolygonVertices(for polylines: [Polyline]) -> [GLBatchVertex]? {
        guard polylines.count == 1,
              let points = normalizedPolygonPoints(polylines[0].points),
              points.count <= 4,
              isConvex(points) else {
            return nil
        }

        return triangleFanVertices(for: points)
    }

    /// Triangulates every flattened subpath as an oriented triangle fan for stencil accumulation.
    /// - Parameter path: The path whose fill contours will be flattened.
    /// - Returns: Triangle vertices preserving each contour's point order.
    static func stencilVertices(for path: CGPath) -> [GLBatchVertex] {
        stencilVertices(for: PathFlattener.flatten(path))
    }

    /// Triangulates every flattened subpath as an oriented triangle fan for stencil accumulation.
    /// - Parameter polylines: The flattened path subpaths.
    /// - Returns: Triangle vertices preserving each contour's point order.
    static func stencilVertices(for polylines: [Polyline]) -> [GLBatchVertex] {
        polylines.reduce(into: [GLBatchVertex]()) { vertices, polyline in
            guard let points = normalizedPolygonPoints(polyline.points) else { return }
            vertices.append(contentsOf: triangleFanVertices(for: points))
        }
    }

    /// Expands a path into the fill triangles for its requested stroke outline.
    /// - Parameters:
    ///   - path: The path whose centerline will be stroked.
    ///   - style: The line width, caps, joins, miter limit, and dash pattern.
    /// - Returns: The triangles that cover the stroke outline contours.
    static func strokeVertices(for path: CGPath, style: StrokeStyle) -> [GLBatchVertex] {
        let polylines = PathFlattener.flatten(path)
        return stencilVertices(for: Stroker.outline(polylines, style: style))
    }

    /// Creates two triangles that cover the destination.
    /// - Parameter size: The destination dimensions in pixels.
    /// - Returns: Six vertices covering the destination bounds.
    static func coverVertices(for size: CGSize) -> [GLBatchVertex] {
        let points = [
            CGPoint.zero,
            CGPoint(x: size.width, y: 0),
            CGPoint(x: size.width, y: size.height),
            CGPoint(x: 0, y: size.height)
        ]
        return [0, 1, 2, 0, 2, 3].map { index in
            let point = points[index]
            return GLBatchVertex(
                positionX: Float(point.x),
                positionY: Float(point.y),
                textureX: 0,
                textureY: 0
            )
        }
    }

    /// Triangulates the transformed image quad and assigns orientation-aware texture coordinates.
    /// - Parameters:
    ///   - destination: The four destination corners in lower-left, lower-right, upper-right, upper-left order.
    ///   - imageSize: The image dimensions in pixels.
    ///   - byTiling: Whether texture coordinates repeat at the image's native pixel size.
    /// - Returns: Six vertices, or nil for an invalid quad or empty image.
    static func imageVertices(
        for destination: [CGPoint],
        imageSize: CGSize,
        byTiling: Bool
    ) -> [GLBatchVertex]? {
        guard destination.count == 4, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let horizontalRepeat = byTiling ? distance(destination[0], destination[1]) / imageSize.width : 1
        let verticalRepeat = byTiling ? distance(destination[0], destination[3]) / imageSize.height : 1
        let textureCoordinates = [
            CGPoint(x: 0, y: verticalRepeat),
            CGPoint(x: horizontalRepeat, y: verticalRepeat),
            CGPoint(x: horizontalRepeat, y: 0),
            CGPoint(x: 0, y: 0)
        ]

        return [0, 1, 2, 0, 2, 3].map { index in
            let point = destination[index]
            let textureCoordinate = textureCoordinates[index]
            return GLBatchVertex(
                positionX: Float(point.x),
                positionY: Float(point.y),
                textureX: Float(textureCoordinate.x),
                textureY: Float(textureCoordinate.y)
            )
        }
    }

    /// Triangulates four points that form an affine-transformed rectangle.
    /// - Parameter points: The rectangle corners in path order.
    /// - Returns: Six vertices, or nil when the points do not form a parallelogram.
    private static func vertices(for points: [CGPoint]) -> [GLBatchVertex]? {
        guard points.count == 4 else { return nil }
        let scale = max(
            1,
            points.reduce(0) { max($0, max(abs($1.x), abs($1.y))) }
        )
        guard abs(points[0].x + points[2].x - points[1].x - points[3].x) <= scale * 1e-10,
              abs(points[0].y + points[2].y - points[1].y - points[3].y) <= scale * 1e-10 else {
            return nil
        }

        return [0, 1, 2, 0, 2, 3].map { index in
            let point = points[index]
            return GLBatchVertex(
                positionX: Float(point.x),
                positionY: Float(point.y),
                textureX: 0,
                textureY: 0
            )
        }
    }

    /// Removes redundant closing points and consecutive duplicate points.
    private static func normalizedPolygonPoints(_ points: [CGPoint]) -> [CGPoint]? {
        var normalized: [CGPoint] = []
        for point in points where normalized.last != point {
            normalized.append(point)
        }
        if normalized.count > 1, normalized.first == normalized.last {
            normalized.removeLast()
        }
        return normalized.count >= 3 ? normalized : nil
    }

    /// Returns the Euclidean distance between two points.
    private static func distance(_ first: CGPoint, _ second: CGPoint) -> Double {
        let dx = second.x - first.x
        let dy = second.y - first.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Checks that every polygon edge has all other vertices on the same side.
    private static func isConvex(_ points: [CGPoint]) -> Bool {
        guard points.count >= 3 else { return false }
        let scale = max(1, points.reduce(0) { max($0, max(abs($1.x), abs($1.y))) })
        let epsilon = scale * scale * 1e-12
        var orientation = 0.0

        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            for otherIndex in points.indices where otherIndex != index && otherIndex != (index + 1) % points.count {
                let point = points[otherIndex]
                let cross = (end.x - start.x) * (point.y - start.y)
                    - (end.y - start.y) * (point.x - start.x)
                guard abs(cross) > epsilon else { continue }
                if orientation == 0 {
                    orientation = cross > 0 ? 1 : -1
                } else if cross * orientation < -epsilon {
                    return false
                }
            }
        }

        return orientation != 0
    }

    /// Converts an ordered polygon into triangles without changing its orientation.
    private static func triangleFanVertices(for points: [CGPoint]) -> [GLBatchVertex] {
        guard points.count >= 3 else { return [] }
        var vertices: [GLBatchVertex] = []
        vertices.reserveCapacity((points.count - 2) * 3)

        for index in 1..<(points.count - 1) {
            for point in [points[0], points[index], points[index + 1]] {
                vertices.append(
                    GLBatchVertex(
                        positionX: Float(point.x),
                        positionY: Float(point.y),
                        textureX: 0,
                        textureY: 0
                    )
                )
            }
        }
        return vertices
    }

    /// Builds a pixel-to-clip-space orthographic projection matrix.
    /// - Parameter size: The render destination dimensions in pixels.
    /// - Returns: A column-major 4×4 matrix, or nil for an empty destination.
    static func orthographicProjection(for size: CGSize) -> [Float]? {
        guard size.width > 0, size.height > 0 else { return nil }

        let width = Float(size.width)
        let height = Float(size.height)
        return [
            2 / width, 0, 0, 0,
            0, 2 / height, 0, 0,
            0, 0, -1, 0,
            -1, -1, 0, 1
        ]
    }

    /// Converts supported color-space components to the shader's RGBA input.
    /// - Parameter color: The color to convert.
    /// - Returns: Four RGBA values, or nil for unsupported or incomplete color data.
    static func rgbaComponents(for color: CGColor) -> [Float]? {
        guard let colorSpace = color.colorSpace else { return nil }

        switch colorSpace.model {
        case .rgb:
            guard color.components.count == 4 else { return nil }
            return color.components.map(Float.init)
        case .gray:
            guard color.components.count == 2 else { return nil }
            let gray = Float(color.components[0])
            return [gray, gray, gray, Float(color.components[1])]
        case .cmyk:
            guard color.components.count == 5 else { return nil }
            let cyan = color.components[0]
            let magenta = color.components[1]
            let yellow = color.components[2]
            let black = color.components[3]
            let alpha = color.components[4]
            return [
                Float((1 - cyan) * (1 - black)),
                Float((1 - magenta) * (1 - black)),
                Float((1 - yellow) * (1 - black)),
                Float(alpha)
            ]
        case .deviceN, .lab:
            return nil
        }
    }
}

/// Renders supported path commands with a cached solid-color OpenGL program.
@MainActor
final class GLRenderer: CGRenderBackend, CGPixelSurfaceRenderer, CGPixelReadbackRenderer {
    /// Keeps the compiled programs alive for the lifetime of the renderer.
    private let shaderCache: GLShaderCache

    /// The solid-color program reused for each rectangle draw.
    private let program: GLProgram

    /// The textured program used for image draw commands.
    private let imageProgram: GLProgram

    /// The reusable vertex batch buffer.
    private let batchBuffer: GLBatchBuffer

    /// The textures reused across image draw commands.
    private let textureCache: GLTextureCache

    /// Creates the shader program and reusable geometry buffers.
    /// - Parameters:
    ///   - shaderCache: The cache from which the solid-color program is loaded.
    ///   - batchBufferDriver: The driver used to allocate and draw vertex buffers.
    /// - Throws: A shader loading, compilation, linking, or buffer allocation error.
    init(
        shaderCache: GLShaderCache = GLShaderCache(),
        batchBufferDriver: any GLBatchBufferDriver = OpenGLBatchBufferDriver()
    ) throws {
        self.shaderCache = shaderCache
        program = try shaderCache.program(for: .solidColor)
        imageProgram = try shaderCache.program(for: .image)
        batchBuffer = try GLBatchBuffer(driver: batchBufferDriver)
        textureCache = GLTextureCache()
    }

    /// Executes commands synchronously on the main actor that owns the GL context.
    /// - Parameters:
    ///   - commands: The backend-independent draw commands to render.
    ///   - size: The destination dimensions in pixels.
    nonisolated func execute(_ commands: [DrawCommand], size: CGSize) {
        MainActor.assumeIsolated {
            executeOnMainActor(commands, size: size)
        }
    }

    /// Replaces the cached surface texture and draws it across the window.
    /// - Parameters:
    ///   - image: The current immutable pixel snapshot.
    ///   - size: The destination dimensions in pixels.
    nonisolated func renderSoftwareSurface(_ image: CGImageSnapshot, size: CGSize) {
        MainActor.assumeIsolated {
            guard let projection = GLRendererGeometry.orthographicProjection(for: size) else { return }
            renderImage(
                image,
                destination: [
                    .zero,
                    CGPoint(x: size.width, y: 0),
                    CGPoint(x: size.width, y: size.height),
                    CGPoint(x: 0, y: size.height)
                ],
                interpolationQuality: .none,
                byTiling: false,
                blendMode: .normal,
                projection: projection,
                updateTexture: true
            )
        }
    }

    /// Reads the current framebuffer as bottom-up RGBA pixel data.
    /// - Parameter size: The framebuffer dimensions in pixels.
    /// - Returns: The framebuffer bytes, or nil when the requested size is invalid.
    nonisolated func readPixels(size: CGSize) -> [UInt8]? {
        MainActor.assumeIsolated {
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0,
                  size.width <= Double(Int32.max),
                  size.height <= Double(Int32.max),
                  size.width.rounded(.towardZero) == size.width,
                  size.height.rounded(.towardZero) == size.height else {
                return nil
            }

            let width = Int(size.width)
            let height = Int(size.height)
            let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
            let (byteCount, sizeOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
            guard rowOverflow == false, sizeOverflow == false else { return nil }

            var pixels = [UInt8](repeating: 0, count: byteCount)
            var didReadPixels = false
            pixels.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                glad_glReadPixels(
                    0,
                    0,
                    GLsizei(width),
                    GLsizei(height),
                    GLenum(GL_RGBA),
                    GLenum(GL_UNSIGNED_BYTE),
                    baseAddress
                )
                didReadPixels = true
            }
            return didReadPixels ? pixels : nil
        }
    }

    /// Renders path fills and batches adjacent commands with matching state.
    /// - Parameters:
    ///   - commands: The backend-independent draw commands to render.
    ///   - size: The destination dimensions in pixels.
    private func executeOnMainActor(_ commands: [DrawCommand], size: CGSize) {
        guard let projection = GLRendererGeometry.orthographicProjection(for: size) else { return }

        program.use()
        setProjection(projection)
        var currentColor: [Float]?

        for command in commands {
            switch command {
            case let .fillPath(path, rule, color, blendMode):
                renderFillPath(
                    path,
                    rule: rule,
                    color: color,
                    blendMode: blendMode,
                    size: size,
                    currentColor: &currentColor
                )
            case let .strokePath(path, color, style, blendMode):
                guard let rgba = GLRendererGeometry.rgbaComponents(for: color) else { continue }
                batchBuffer.flush()
                let vertices = GLRendererGeometry.strokeVertices(for: path, style: style)
                if renderStencilFill(
                    vertices,
                    rule: .winding,
                    rgba: rgba,
                    blendMode: blendMode,
                    size: size
                ) {
                    currentColor = rgba
                }
            case let .drawImage(image, destination, interpolationQuality, byTiling, blendMode):
                renderImage(
                    image,
                    destination: destination,
                    interpolationQuality: interpolationQuality,
                    byTiling: byTiling,
                    blendMode: blendMode,
                    projection: projection
                )
                currentColor = nil
            default:
                continue
            }
        }

        batchBuffer.flush()
    }

    /// Draws an image quad using its cached texture and the textured shader.
    /// - Parameters:
    ///   - image: The immutable image state captured by the drawing context.
    ///   - destination: The transformed destination corners.
    ///   - interpolationQuality: The requested texture sampling quality.
    ///   - byTiling: Whether the texture coordinates repeat beyond one image.
    ///   - blendMode: The compositing mode captured by the drawing context.
    ///   - projection: The destination's pixel-to-clip-space projection matrix.
    private func renderImage(
        _ image: CGImageSnapshot,
        destination: [CGPoint],
        interpolationQuality: CGInterpolationQuality,
        byTiling: Bool,
        blendMode: CGBlendMode,
        projection: [Float],
        updateTexture: Bool = false
    ) {
        guard let vertices = GLRendererGeometry.imageVertices(
            for: destination,
            imageSize: CGSize(width: image.width, height: image.height),
            byTiling: byTiling
        ) else {
            return
        }

        batchBuffer.flush()
        let texture: GLTexture
        do {
            texture = try updateTexture
                ? textureCache.updateTexture(for: image)
                : textureCache.texture(for: image)
        } catch {
            preconditionFailure("Could not create texture for image draw command: \(error)")
        }

        texture.setInterpolationQuality(interpolationQuality)
        imageProgram.use()
        setProjection(projection, for: imageProgram)
        glad_glUniform1i(imageProgram.uniformLocation(named: "uImage"), 0)
        let vertexData = vertices.flatMap { [$0.positionX, $0.positionY, $0.textureX, $0.textureY] }
        do {
            try batchBuffer.append(
                vertices: vertexData,
                state: GLBatchState(
                    program: imageProgram.identifier,
                    texture: texture.identifier,
                    blendMode: blendMode
                )
            )
        } catch {
            preconditionFailure("Image quad produced incomplete vertex data: \(error)")
        }
        batchBuffer.flush()
    }

    /// Draws a fill command directly for simple geometry or through the stencil buffer for complex paths.
    private func renderFillPath(
        _ path: CGPath,
        rule: CGPath.CGPathFillRule,
        color: CGColor,
        blendMode: CGBlendMode,
        size: CGSize,
        currentColor: inout [Float]?
    ) {
        guard let rgba = GLRendererGeometry.rgbaComponents(for: color) else { return }

        let vertices: [GLBatchVertex]
        if let rectangleVertices = GLRendererGeometry.rectangleVertices(for: path) {
            vertices = rectangleVertices
        } else {
            let polylines = PathFlattener.flatten(path)
            if let convexVertices = GLRendererGeometry.convexPolygonVertices(for: polylines) {
                vertices = convexVertices
            } else {
                batchBuffer.flush()
                let stencilVertices = GLRendererGeometry.stencilVertices(for: polylines)
                if renderStencilFill(
                    stencilVertices,
                    rule: rule,
                    rgba: rgba,
                    blendMode: blendMode,
                    size: size
                ) {
                    currentColor = rgba
                }
                return
            }
        }

        if currentColor != rgba {
            batchBuffer.flush()
            setColor(rgba)
            currentColor = rgba
        }

        let vertexData = vertices.flatMap { [$0.positionX, $0.positionY, $0.textureX, $0.textureY] }
        do {
            try batchBuffer.append(
                vertices: vertexData,
                state: GLBatchState(program: program.identifier, texture: nil, blendMode: blendMode)
            )
        } catch {
            preconditionFailure("Path triangulation produced incomplete vertex data: \(error)")
        }
    }

    /// Fills an arbitrary path by accumulating its contour winding in the stencil buffer.
    private func renderStencilFill(
        _ vertices: [GLBatchVertex],
        rule: CGPath.CGPathFillRule,
        rgba: [Float],
        blendMode: CGBlendMode,
        size: CGSize
    ) -> Bool {
        guard vertices.isEmpty == false else { return false }

        glad_glEnable(GLenum(GL_STENCIL_TEST))
        glad_glStencilMask(GLuint(0xFF))
        glad_glClearStencil(0)
        glad_glClear(GLbitfield(GL_STENCIL_BUFFER_BIT))
        glad_glColorMask(GLboolean(GL_FALSE), GLboolean(GL_FALSE), GLboolean(GL_FALSE), GLboolean(GL_FALSE))
        glad_glStencilFunc(GLenum(GL_ALWAYS), 0, GLuint(0xFF))

        switch rule {
        case .winding:
            glad_glStencilOpSeparate(GLenum(GL_FRONT), GLenum(GL_KEEP), GLenum(GL_KEEP), GLenum(GL_INCR_WRAP))
            glad_glStencilOpSeparate(GLenum(GL_BACK), GLenum(GL_KEEP), GLenum(GL_KEEP), GLenum(GL_DECR_WRAP))
        case .evenOdd:
            glad_glStencilOp(GLenum(GL_KEEP), GLenum(GL_KEEP), GLenum(GL_INVERT))
        }

        appendAndFlush(vertices, blendMode: blendMode)

        glad_glColorMask(GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE))
        glad_glStencilFunc(GLenum(GL_NOTEQUAL), 0, GLuint(0xFF))
        glad_glStencilOp(GLenum(GL_KEEP), GLenum(GL_KEEP), GLenum(GL_KEEP))
        setColor(rgba)
        appendAndFlush(GLRendererGeometry.coverVertices(for: size), blendMode: blendMode)

        glad_glStencilMask(GLuint(0xFF))
        glad_glDisable(GLenum(GL_STENCIL_TEST))
        return true
    }

    /// Appends geometry for the solid-color program and immediately draws it.
    private func appendAndFlush(_ vertices: [GLBatchVertex], blendMode: CGBlendMode) {
        let vertexData = vertices.flatMap { [$0.positionX, $0.positionY, $0.textureX, $0.textureY] }
        do {
            try batchBuffer.append(
                vertices: vertexData,
                state: GLBatchState(program: program.identifier, texture: nil, blendMode: blendMode)
            )
        } catch {
            preconditionFailure("Path triangulation produced incomplete vertex data: \(error)")
        }
        batchBuffer.flush()
    }

    /// Sends the column-major projection matrix to the solid-color program.
    /// - Parameter values: The 16 projection matrix values.
    private func setProjection(_ values: [Float]) {
        setProjection(values, for: program)
    }

    /// Sends the column-major projection matrix to a shader program.
    /// - Parameters:
    ///   - values: The 16 projection matrix values.
    ///   - program: The shader program that receives the matrix.
    private func setProjection(_ values: [Float], for program: GLProgram) {
        let location = program.uniformLocation(named: "uProjection")
        values.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            glad_glUniformMatrix4fv(location, 1, GLboolean(GL_FALSE), baseAddress)
        }
    }

    /// Sends the current fill color to the solid-color program.
    /// - Parameter components: Four RGBA values.
    private func setColor(_ components: [Float]) {
        let location = program.uniformLocation(named: "uColor")
        glad_glUniform4f(location, components[0], components[1], components[2], components[3])
    }
}
