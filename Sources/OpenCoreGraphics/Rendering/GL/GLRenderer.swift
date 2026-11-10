@preconcurrency import OpenGLAD

/// Converts rectangle paths and destination dimensions into OpenGL geometry.
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
final class GLRenderer: CGRenderBackend {
    /// Keeps the compiled programs alive for the lifetime of the renderer.
    private let shaderCache: GLShaderCache

    /// The solid-color program reused for each rectangle draw.
    private let program: GLProgram

    /// The reusable vertex batch buffer.
    private let batchBuffer: GLBatchBuffer

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
        batchBuffer = try GLBatchBuffer(driver: batchBufferDriver)
    }

    /// Executes commands synchronously on the main actor that owns the GL context.
    /// - Parameters:
    ///   - commands: The backend-independent draw commands to render.
    ///   - size: The destination dimensions in pixels.
    func execute(_ commands: [DrawCommand], size: CGSize) {
        executeOnMainActor(commands, size: size)
    }

    /// Renders opaque rectangle fills and batches adjacent commands with matching state.
    /// - Parameters:
    ///   - commands: The backend-independent draw commands to render.
    ///   - size: The destination dimensions in pixels.
    private func executeOnMainActor(_ commands: [DrawCommand], size: CGSize) {
        guard let projection = GLRendererGeometry.orthographicProjection(for: size) else { return }

        program.use()
        setProjection(projection)
        var currentColor: [Float]?

        for command in commands {
            guard case let .fillPath(path, _, color, blendMode) = command,
                  let vertices = GLRendererGeometry.rectangleVertices(for: path),
                  let rgba = GLRendererGeometry.rgbaComponents(for: color) else {
                continue
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
                preconditionFailure("Rectangle triangulation produced incomplete vertex data: \(error)")
            }
        }

        batchBuffer.flush()
    }

    /// Sends the column-major projection matrix to the solid-color program.
    /// - Parameter values: The 16 projection matrix values.
    private func setProjection(_ values: [Float]) {
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
