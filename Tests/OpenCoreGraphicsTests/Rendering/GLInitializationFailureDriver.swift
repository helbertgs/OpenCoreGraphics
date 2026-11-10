import Testing
@preconcurrency import OpenGLAD
import OpenGLFW
@testable import OpenCoreGraphics

/// Compiles actual programs and injects a failure after successful partial initialization.
@MainActor
final class GLInitializationFailureDriver: GLProgramDriver {
    /// The OpenGL driver that creates and deletes actual program objects.
    private let driver = OpenGLProgramDriver()
    /// Whether compilation should fail after two programs.
    private let failCompilation: Bool
    /// The context in which the first program was created.
    private(set) var owner: OpaquePointer?
    /// Successfully allocated program identifiers.
    private(set) var created: [UInt32] = []
    /// Program identifiers actually deleted.
    private(set) var deleted: [UInt32] = []

    /// Creates an observing driver for the requested failure point.
    init(failCompilation: Bool) {
        self.failCompilation = failCompilation
    }

    /// Creates a real program or injects the configured partial failure.
    func compileProgram(vertexSource: String, fragmentSource: String) throws -> UInt32 {
        let context = glfwGetCurrentContext()
        if owner == nil { owner = context }
        #expect(context != nil)
        #expect(context == owner)
        if failCompilation && created.count == 2 { throw GLProgramError.programCreationFailed }
        let program = try driver.compileProgram(vertexSource: vertexSource, fragmentSource: fragmentSource)
        created.append(program)
        return program
    }

    /// Delegates uniform lookup to the real driver.
    func uniformLocation(program: UInt32, name: String) -> Int32 {
        driver.uniformLocation(program: program, name: name)
    }

    /// Delegates program activation to the real driver.
    func useProgram(_ program: UInt32) {
        driver.useProgram(program)
    }

    /// Deletes one real program in the context that allocated it.
    func deleteProgram(_ program: UInt32) {
        #expect(glfwGetCurrentContext() == owner)
        #expect(created.contains(program))
        #expect(deleted.contains(program) == false)
        #expect(glad_glIsProgram(program) == GL_TRUE)
        driver.deleteProgram(program)
        #expect(glad_glIsProgram(program) == GL_FALSE)
        deleted.append(program)
    }
}
