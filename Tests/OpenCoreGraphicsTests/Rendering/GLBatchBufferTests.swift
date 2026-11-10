import Testing
@testable import OpenCoreGraphics

/// Tests batch grouping and reusable buffer ownership without a GL context.
@MainActor
struct GLBatchBufferTests {
    /// Verifies five inputs with two consecutive states produce two batches.
    @Test
    func groupsVerticesByConsecutiveRenderState() throws {
        let driver = RecordingGLBatchBufferDriver()
        let buffer = try GLBatchBuffer(driver: driver)
        let firstState = GLBatchState(program: 1, texture: nil, blendMode: .normal)
        let secondState = GLBatchState(program: 2, texture: 7, blendMode: .multiply)

        for _ in 0..<3 {
            try buffer.append(vertices: [0, 0, 0, 0], state: firstState)
        }
        for _ in 0..<2 {
            try buffer.append(vertices: [1, 1, 1, 1], state: secondState)
        }
        buffer.flush()

        #expect(driver.createCount == 1)
        #expect(driver.uploadCount == 2)
        #expect(driver.drawVertexCounts == [3, 2])
        #expect(driver.drawStates == [firstState, secondState])
        #expect(driver.uploadedVertices == [
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [1, 1, 1, 1, 1, 1, 1, 1]
        ])
    }

    /// Verifies malformed vertex data throws without submitting a partial batch.
    @Test
    func rejectsIncompleteVertexTuples() throws {
        let driver = RecordingGLBatchBufferDriver()
        let buffer = try GLBatchBuffer(driver: driver)
        let state = GLBatchState(program: 1, texture: nil, blendMode: .normal)

        #expect(throws: GLBatchBufferError.invalidVertexData) {
            try buffer.append(vertices: [0, 1, 2], state: state)
        }
        buffer.flush()

        #expect(driver.uploadCount == 0)
        #expect(driver.drawVertexCounts.isEmpty)
    }

    /// Verifies deinitialization deletes the reusable vertex array and buffer.
    @Test
    func deinitializationDeletesBuffers() throws {
        let driver = RecordingGLBatchBufferDriver()
        var buffer: GLBatchBuffer? = try GLBatchBuffer(driver: driver)

        buffer = nil

        #expect(buffer == nil)
        #expect(driver.deletedVertexArrays == [11])
        #expect(driver.deletedVertexBuffers == [12])
    }
}

/// Records OpenGL batch-buffer operations for unit tests.
@MainActor
private final class RecordingGLBatchBufferDriver: GLBatchBufferDriver {
    /// The number of vertex array and buffer allocations.
    private(set) var createCount = 0

    /// The number of vertex data uploads.
    private(set) var uploadCount = 0

    /// Vertex values passed to each upload.
    private(set) var uploadedVertices: [[Float]] = []

    /// The vertex counts passed to each draw call.
    private(set) var drawVertexCounts: [Int] = []

    /// The state passed to each draw call.
    private(set) var drawStates: [GLBatchState] = []

    /// The vertex array identifiers passed to deletion.
    private(set) var deletedVertexArrays: [UInt32] = []

    /// The vertex buffer identifiers passed to deletion.
    private(set) var deletedVertexBuffers: [UInt32] = []

    /// Creates stable fake identifiers for the batch buffers.
    /// - Returns: A fake vertex array and vertex buffer pair.
    func createBuffers() throws -> (vertexArray: UInt32, vertexBuffer: UInt32) {
        createCount += 1
        return (11, 12)
    }

    /// Records a vertex upload for later assertions.
    /// - Parameters:
    ///   - vertices: The interleaved vertices.
    ///   - vertexArray: The fake vertex array identifier.
    ///   - vertexBuffer: The fake vertex buffer identifier.
    func upload(vertices: [Float], vertexArray: UInt32, vertexBuffer: UInt32) {
        uploadCount += 1
        uploadedVertices.append(vertices)
    }

    /// Records a batch draw for later assertions.
    /// - Parameters:
    ///   - vertexCount: The number of vertices to draw.
    ///   - state: The captured render state.
    func draw(vertexCount: Int, state: GLBatchState) {
        drawVertexCounts.append(vertexCount)
        drawStates.append(state)
    }

    /// Records deletion of the fake vertex array and vertex buffer.
    /// - Parameters:
    ///   - vertexArray: The fake vertex array identifier.
    ///   - vertexBuffer: The fake vertex buffer identifier.
    func deleteBuffers(vertexArray: UInt32, vertexBuffer: UInt32) {
        deletedVertexArrays.append(vertexArray)
        deletedVertexBuffers.append(vertexBuffer)
    }
}
