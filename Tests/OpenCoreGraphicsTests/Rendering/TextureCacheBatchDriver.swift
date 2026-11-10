@testable import OpenCoreGraphics

/// Records batch submissions and texture releases in their observed order.
@MainActor
final class TextureCacheBatchDriver: GLBatchBufferDriver {
    /// Ordered batch and texture events.
    var events: [String] = []

    /// Vertex values submitted by the pending batch.
    private(set) var uploadedVertices: [Float] = []

    /// State used to draw the pending batch.
    private(set) var drawnState: GLBatchState?

    /// Creates fake buffer identifiers.
    func createBuffers() throws -> (vertexArray: UInt32, vertexBuffer: UInt32) {
        (1, 2)
    }

    /// Records vertex values without using OpenGL.
    func upload(vertices: [Float], vertexArray: UInt32, vertexBuffer: UInt32) {
        uploadedVertices = vertices
        events.append("upload")
    }

    /// Records the draw state and texture identifier.
    func draw(vertexCount: Int, state: GLBatchState) {
        drawnState = state
        events.append("draw \(state.texture ?? 0)")
    }

    /// Accepts fake buffer deletion.
    func deleteBuffers(vertexArray: UInt32, vertexBuffer: UInt32) {}
}
