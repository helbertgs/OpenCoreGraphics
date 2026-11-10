import Testing
@testable import OpenCoreGraphics

/// Tests shader program reuse without initializing an OpenGL context.
@MainActor
struct GLShaderCacheTests {
    /// Verifies repeated requests reuse the same compiled program.
    @Test
    func repeatedRequestsCompileOnce() throws {
        let driver = RecordingGLProgramDriver()
        let cache = GLShaderCache(driver: driver)

        let first = try cache.program(for: .solidColor)
        let second = try cache.program(for: .solidColor)
        let third = try cache.program(for: .solidColor)

        #expect(first === second)
        #expect(second === third)
        #expect(driver.compileCount == 1)
    }

    /// Verifies different shader kinds receive separate compiled programs.
    @Test
    func differentKindsCompileSeparatePrograms() throws {
        let driver = RecordingGLProgramDriver()
        let cache = GLShaderCache(driver: driver)

        let solidColor = try cache.program(for: .solidColor)
        let image = try cache.program(for: .image)

        #expect(solidColor !== image)
        #expect(driver.compileCount == 2)
    }

    /// Verifies typed compilation errors propagate without caching a failed program.
    @Test
    func compilationErrorsPropagate() {
        let driver = RecordingGLProgramDriver()
        driver.compilationError = .shaderCompilationFailed(stage: "vertex", log: "invalid shader")
        let cache = GLShaderCache(driver: driver)

        #expect(throws: GLProgramError.self) {
            try cache.program(for: .solidColor)
        }
        #expect(driver.compileCount == 1)
    }

    /// Verifies each requested uniform location is queried only once.
    @Test
    func uniformLocationsAreCached() throws {
        let driver = RecordingGLProgramDriver()
        let program = try GLProgram(vertexSource: "vertex", fragmentSource: "fragment", driver: driver)

        #expect(program.uniformLocation(named: "uColor") == 3)
        #expect(program.uniformLocation(named: "uColor") == 3)
        #expect(driver.uniformLocationCount == 1)

        program.use()
        #expect(driver.usedProgram == program.identifier)
    }

    /// Verifies releasing a program deletes its OpenGL identifier on the actor.
    @Test
    func deinitializationDeletesProgram() throws {
        let driver = RecordingGLProgramDriver()
        var program: GLProgram? = try GLProgram(
            vertexSource: "vertex",
            fragmentSource: "fragment",
            driver: driver
        )
        let identifier = try #require(program?.identifier)

        program = nil

        #expect(driver.deletedPrograms == [identifier])
    }
}

/// Records program operations for shader cache tests.
@MainActor
private final class RecordingGLProgramDriver: GLProgramDriver {
    /// The error to throw in place of a successful compilation.
    var compilationError: GLProgramError?

    /// The number of program compilation requests.
    private(set) var compileCount = 0

    /// The number of uniform location lookups.
    private(set) var uniformLocationCount = 0

    /// The last program passed to `useProgram`.
    private(set) var usedProgram: UInt32?

    /// The program identifiers passed to `deleteProgram`.
    private(set) var deletedPrograms: [UInt32] = []

    /// Simulates compiling and linking a program.
    /// - Parameters:
    ///   - vertexSource: The supplied vertex shader source.
    ///   - fragmentSource: The supplied fragment shader source.
    /// - Returns: A stable test program identifier.
    func compileProgram(vertexSource: String, fragmentSource: String) throws -> UInt32 {
        compileCount += 1
        if let compilationError {
            throw compilationError
        }
        return 42
    }

    /// Simulates looking up a uniform location.
    /// - Parameters:
    ///   - program: The supplied program identifier.
    ///   - name: The requested uniform name.
    /// - Returns: A stable test location.
    func uniformLocation(program: UInt32, name: String) -> Int32 {
        uniformLocationCount += 1
        return 3
    }

    /// Records which test program was made current.
    /// - Parameter program: The supplied program identifier.
    func useProgram(_ program: UInt32) {
        usedProgram = program
    }

    /// Records deletion of a synthetic program identifier.
    /// - Parameter program: The supplied program identifier.
    func deleteProgram(_ program: UInt32) {
        deletedPrograms.append(program)
    }
}
