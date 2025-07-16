import Foundation

public struct CGBuffer : Sendable {

    /// The OpenGL vertex array object (VAO) used for rendering.
    public var vao: UInt32 = 0

    /// The OpenGL vertex buffer object (VBO) used for rendering.
    public var vbo: UInt32 = 0

    /// The OpenGL element buffer object (EBO) used for rendering.
    public var ebo: UInt32 = 0

    /// The OpenGL framebuffer object (FBO) used for rendering.
    public var fbo: UInt32 = 0

    /// The vertices stored in the buffer.
    public var vertices: [Float] = [
        -1.0, -1.0, // bottomLeft
         1.0, -1.0, // bottomRight
         1.0,  1.0, // topRight
        -1.0,  1.0  // topLeft
    ]

    /// The indices stored in the buffer.
    public var indices: [UInt32] = [
        0, 1, 2,
        2, 3, 0
    ]
}