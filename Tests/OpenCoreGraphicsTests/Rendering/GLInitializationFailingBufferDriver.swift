import Testing
@testable import OpenCoreGraphics

/// Injects a buffer allocation error after all real shader programs were compiled.
@MainActor
struct GLInitializationFailingBufferDriver: GLBatchBufferDriver {
    /// Fails before allocating the reusable buffers.
    func createBuffers() throws -> (vertexArray: UInt32, vertexBuffer: UInt32) {
        throw GLBatchBufferError.bufferCreationFailed
    }

    /// Reports an unexpected upload after failed allocation.
    func upload(vertices: [Float], vertexArray: UInt32, vertexBuffer: UInt32) {
        Issue.record("Unexpected buffer upload")
    }

    /// Reports an unexpected draw after failed allocation.
    func draw(vertexCount: Int, state: GLBatchState) {
        Issue.record("Unexpected buffer draw")
    }

    /// Reports unexpected deletion of buffers that were never allocated.
    func deleteBuffers(vertexArray: UInt32, vertexBuffer: UInt32) {
        Issue.record("Unexpected buffer deletion")
    }
}
