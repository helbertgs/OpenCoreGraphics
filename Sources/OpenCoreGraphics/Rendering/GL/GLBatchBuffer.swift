@preconcurrency import OpenGLAD

/// One interleaved position and texture-coordinate pair for batch rendering.
struct GLBatchVertex: Equatable, Sendable {
    /// The horizontal position in device-space pixels.
    let positionX: Float

    /// The vertical position in device-space pixels.
    let positionY: Float

    /// The horizontal image texture coordinate.
    let textureX: Float

    /// The vertical image texture coordinate.
    let textureY: Float
}

/// The immutable OpenGL state that must remain constant within a vertex batch.
struct GLBatchState: Equatable, Hashable, Sendable {
    /// The linked OpenGL program identifier.
    let program: UInt32

    /// The texture identifier, or nil when the batch has no texture.
    let texture: UInt32?

    /// The compositing mode for the batch.
    let blendMode: CGBlendMode
}

/// A typed failure raised while allocating reusable batch buffers.
enum GLBatchBufferError: Error, Equatable, Sendable {
    /// OpenGL could not allocate both a vertex array and vertex buffer.
    case bufferCreationFailed

    /// Vertex values do not contain complete position and texture-coordinate tuples.
    case invalidVertexData
}

/// Performs OpenGL vertex-buffer operations for a batch buffer.
@MainActor
protocol GLBatchBufferDriver {
    /// Creates and configures one vertex array and one dynamic vertex buffer.
    /// - Returns: The vertex array and vertex buffer identifiers.
    /// - Throws: `GLBatchBufferError.bufferCreationFailed` if allocation fails.
    func createBuffers() throws -> (vertexArray: UInt32, vertexBuffer: UInt32)

    /// Replaces the dynamic vertex data for the current batch.
    /// - Parameters:
    ///   - vertices: Interleaved position and texture-coordinate float values.
    ///   - vertexArray: The vertex array identifier.
    ///   - vertexBuffer: The vertex buffer identifier.
    func upload(vertices: [Float], vertexArray: UInt32, vertexBuffer: UInt32)

    /// Draws a batch using its captured render state.
    /// - Parameters:
    ///   - vertexCount: The number of vertices to draw.
    ///   - state: The program, texture, and blend mode for this batch.
    func draw(vertexCount: Int, state: GLBatchState)

    /// Deletes the reusable vertex array and vertex buffer.
    /// - Parameters:
    ///   - vertexArray: The vertex array identifier.
    ///   - vertexBuffer: The vertex buffer identifier.
    func deleteBuffers(vertexArray: UInt32, vertexBuffer: UInt32)
}

/// Implements dynamic vertex-buffer operations with OpenGLAD.
@MainActor
struct OpenGLBatchBufferDriver: GLBatchBufferDriver {
    /// Creates and configures reusable vertex input objects.
    /// - Returns: The vertex array and vertex buffer identifiers.
    /// - Throws: `GLBatchBufferError.bufferCreationFailed` if allocation fails.
    func createBuffers() throws -> (vertexArray: UInt32, vertexBuffer: UInt32) {
        var vertexArray: GLuint = 0
        var vertexBuffer: GLuint = 0
        glad_glGenVertexArrays(1, &vertexArray)
        glad_glGenBuffers(1, &vertexBuffer)

        guard vertexArray != 0, vertexBuffer != 0 else {
            if vertexArray != 0 {
                glad_glDeleteVertexArrays(1, &vertexArray)
            }
            if vertexBuffer != 0 {
                glad_glDeleteBuffers(1, &vertexBuffer)
            }
            throw GLBatchBufferError.bufferCreationFailed
        }

        glad_glBindVertexArray(vertexArray)
        glad_glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer)
        glad_glEnableVertexAttribArray(0)
        glad_glVertexAttribPointer(
            0,
            2,
            GLenum(GL_FLOAT),
            GLboolean(GL_FALSE),
            GLsizei(4 * MemoryLayout<Float>.stride),
            nil
        )
        glad_glEnableVertexAttribArray(1)
        let textureCoordinateOffset = UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride)
        glad_glVertexAttribPointer(
            1,
            2,
            GLenum(GL_FLOAT),
            GLboolean(GL_FALSE),
            GLsizei(4 * MemoryLayout<Float>.stride),
            textureCoordinateOffset
        )

        return (vertexArray, vertexBuffer)
    }

    /// Uploads interleaved vertices to the reusable dynamic buffer.
    /// - Parameters:
    ///   - vertices: Interleaved position and texture-coordinate float values.
    ///   - vertexArray: The vertex array identifier.
    ///   - vertexBuffer: The vertex buffer identifier.
    func upload(vertices: [Float], vertexArray: UInt32, vertexBuffer: UInt32) {
        glad_glBindVertexArray(vertexArray)
        glad_glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer)
        vertices.withUnsafeBytes { bytes in
            glad_glBufferData(
                GLenum(GL_ARRAY_BUFFER),
                GLsizeiptr(bytes.count),
                bytes.baseAddress,
                GLenum(GL_DYNAMIC_DRAW)
            )
        }
    }

    /// Activates the batch program and texture, then draws its triangles.
    /// - Parameters:
    ///   - vertexCount: The number of vertices to draw.
    ///   - state: The program, texture, and blend mode for this batch.
    func draw(vertexCount: Int, state: GLBatchState) {
        let blendConfiguration = GLBlendModeMapper.configuration(for: state.blendMode)
        glad_glEnable(GLenum(GL_BLEND))
        glad_glBlendEquationSeparate(GLenum(GL_FUNC_ADD), GLenum(GL_FUNC_ADD))
        glad_glBlendFuncSeparate(
            blendConfiguration.sourceRGB.openGLValue,
            blendConfiguration.destinationRGB.openGLValue,
            blendConfiguration.sourceAlpha.openGLValue,
            blendConfiguration.destinationAlpha.openGLValue
        )
        glad_glUseProgram(state.program)
        glad_glActiveTexture(GLenum(GL_TEXTURE0))
        glad_glBindTexture(GLenum(GL_TEXTURE_2D), state.texture ?? 0)
        glad_glDrawArrays(GLenum(GL_TRIANGLES), 0, GLsizei(vertexCount))
    }

    /// Deletes the vertex array and vertex buffer.
    /// - Parameters:
    ///   - vertexArray: The vertex array identifier.
    ///   - vertexBuffer: The vertex buffer identifier.
    func deleteBuffers(vertexArray: UInt32, vertexBuffer: UInt32) {
        var vertexArray = vertexArray
        var vertexBuffer = vertexBuffer
        glad_glDeleteVertexArrays(1, &vertexArray)
        glad_glDeleteBuffers(1, &vertexBuffer)
    }
}

/// Collects compatible vertex data and submits it using reusable OpenGL buffers.
@MainActor
final class GLBatchBuffer {
    /// The OpenGL driver that manages and draws the batch buffers.
    private let driver: any GLBatchBufferDriver

    /// The reusable vertex array identifier.
    private let vertexArray: UInt32

    /// The reusable dynamic vertex buffer identifier.
    private let vertexBuffer: UInt32

    /// Interleaved position and texture-coordinate data waiting to be drawn.
    private var vertices: [Float] = []

    /// The render state shared by the pending vertices.
    private var state: GLBatchState?

    /// Creates one reusable vertex array and dynamic vertex buffer.
    /// - Parameter driver: The driver used to allocate and draw the buffers.
    /// - Throws: `GLBatchBufferError.bufferCreationFailed` if OpenGL allocation fails.
    init(driver: any GLBatchBufferDriver = OpenGLBatchBufferDriver()) throws {
        self.driver = driver
        let buffers = try driver.createBuffers()
        vertexArray = buffers.vertexArray
        vertexBuffer = buffers.vertexBuffer
    }

    /// Releases the reusable OpenGL buffers on the main actor.
    isolated deinit {
        driver.deleteBuffers(vertexArray: vertexArray, vertexBuffer: vertexBuffer)
    }

    /// Adds interleaved position and texture-coordinate data to a matching batch.
    /// - Parameters:
    ///   - vertices: Float values in groups of position x/y and texture u/v.
    ///   - state: The program, texture, and blend mode for the vertices.
    /// - Throws: `GLBatchBufferError.invalidVertexData` unless the input has groups of four values.
    func append(vertices newVertices: [Float], state newState: GLBatchState) throws {
        guard newVertices.count.isMultiple(of: 4) else {
            throw GLBatchBufferError.invalidVertexData
        }

        guard newVertices.isEmpty == false else { return }

        if let state, state != newState {
            flush()
        }

        state = newState
        vertices.append(contentsOf: newVertices)
    }

    /// Uploads and draws the pending vertices, then clears the batch for the next frame.
    func flush() {
        guard let state, vertices.isEmpty == false else { return }

        driver.upload(vertices: vertices, vertexArray: vertexArray, vertexBuffer: vertexBuffer)
        driver.draw(vertexCount: vertices.count / 4, state: state)
        vertices.removeAll(keepingCapacity: true)
        self.state = nil
    }
}
