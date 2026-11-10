@preconcurrency import OpenGLAD

/// A typed failure raised while creating or compiling an OpenGL program.
enum GLProgramError: Error, Equatable, Sendable {
    /// OpenGL could not allocate a shader object.
    case shaderCreationFailed(String)

    /// A shader did not compile; the associated text is the OpenGL info log.
    case shaderCompilationFailed(stage: String, log: String)

    /// OpenGL could not allocate a program object.
    case programCreationFailed

    /// A program did not link; the associated text is the OpenGL info log.
    case programLinkFailed(String)
}

/// Performs OpenGL program operations, allowing them to be tested without a GL context.
@MainActor
protocol GLProgramDriver {
    /// Compiles and links a program from its vertex and fragment source.
    /// - Parameters:
    ///   - vertexSource: GLSL source for the vertex shader.
    ///   - fragmentSource: GLSL source for the fragment shader.
    /// - Returns: The OpenGL program identifier.
    /// - Throws: A `GLProgramError` when allocation, compilation, or linking fails.
    func compileProgram(vertexSource: String, fragmentSource: String) throws -> UInt32

    /// Looks up a uniform location in a linked program.
    /// - Parameters:
    ///   - program: The OpenGL program identifier.
    ///   - name: The uniform name.
    /// - Returns: The uniform location, or `-1` when it is not present.
    func uniformLocation(program: UInt32, name: String) -> Int32

    /// Makes a linked program current for rendering.
    /// - Parameter program: The OpenGL program identifier.
    func useProgram(_ program: UInt32)

    /// Releases an OpenGL program identifier.
    /// - Parameter program: The OpenGL program identifier.
    func deleteProgram(_ program: UInt32)
}

/// Implements program operations with functions loaded by OpenGLAD.
@MainActor
struct OpenGLProgramDriver: GLProgramDriver {
    /// Compiles and links vertex and fragment shaders.
    /// - Parameters:
    ///   - vertexSource: GLSL source for the vertex shader.
    ///   - fragmentSource: GLSL source for the fragment shader.
    /// - Returns: The linked OpenGL program identifier.
    /// - Throws: A `GLProgramError` containing the OpenGL info log on failure.
    func compileProgram(vertexSource: String, fragmentSource: String) throws -> UInt32 {
        let vertexShader = try compileShader(vertexSource, type: GLenum(GL_VERTEX_SHADER), stage: "vertex")
        let fragmentShader: UInt32
        do {
            fragmentShader = try compileShader(fragmentSource, type: GLenum(GL_FRAGMENT_SHADER), stage: "fragment")
        } catch {
            glad_glDeleteShader(vertexShader)
            throw error
        }

        defer {
            glad_glDeleteShader(vertexShader)
            glad_glDeleteShader(fragmentShader)
        }

        let program = glad_glCreateProgram()
        guard program != 0 else {
            throw GLProgramError.programCreationFailed
        }

        glad_glAttachShader(program, vertexShader)
        glad_glAttachShader(program, fragmentShader)
        glad_glLinkProgram(program)

        var linkStatus: GLint = 0
        glad_glGetProgramiv(program, GLenum(GL_LINK_STATUS), &linkStatus)
        guard linkStatus == GL_TRUE else {
            let log = programInfoLog(program)
            glad_glDeleteProgram(program)
            throw GLProgramError.programLinkFailed(log)
        }

        return program
    }

    /// Looks up a uniform location using OpenGLAD.
    /// - Parameters:
    ///   - program: The OpenGL program identifier.
    ///   - name: The uniform name.
    /// - Returns: The uniform location, or `-1` when it is not present.
    func uniformLocation(program: UInt32, name: String) -> Int32 {
        glad_glGetUniformLocation(program, name)
    }

    /// Makes the specified OpenGL program current.
    /// - Parameter program: The OpenGL program identifier.
    func useProgram(_ program: UInt32) {
        glad_glUseProgram(program)
    }

    /// Deletes an OpenGL program.
    /// - Parameter program: The OpenGL program identifier.
    func deleteProgram(_ program: UInt32) {
        glad_glDeleteProgram(program)
    }

    /// Compiles one shader stage and includes its info log when compilation fails.
    /// - Parameters:
    ///   - source: GLSL source code for the shader.
    ///   - type: The OpenGL shader stage constant.
    ///   - stage: A readable shader stage name for the thrown error.
    /// - Returns: The compiled shader identifier.
    /// - Throws: A typed error if OpenGL cannot allocate or compile the shader.
    private func compileShader(_ source: String, type: GLenum, stage: String) throws -> UInt32 {
        let shader = glad_glCreateShader(type)
        guard shader != 0 else {
            throw GLProgramError.shaderCreationFailed(stage)
        }

        source.withCString { pointer in
            var sourcePointer: UnsafePointer<GLchar>? = pointer
            glad_glShaderSource(shader, 1, &sourcePointer, nil)
        }
        glad_glCompileShader(shader)

        var compileStatus: GLint = 0
        glad_glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &compileStatus)
        guard compileStatus == GL_TRUE else {
            let log = shaderInfoLog(shader)
            glad_glDeleteShader(shader)
            throw GLProgramError.shaderCompilationFailed(stage: stage, log: log)
        }

        return shader
    }

    /// Reads the info log for a shader object.
    /// - Parameter shader: The shader identifier to inspect.
    /// - Returns: The OpenGL shader info log.
    private func shaderInfoLog(_ shader: UInt32) -> String {
        var length: GLint = 0
        glad_glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &length)
        guard length > 1 else { return "" }

        var buffer = [GLchar](repeating: 0, count: Int(length))
        glad_glGetShaderInfoLog(shader, length, &length, &buffer)
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Reads the info log for a program object.
    /// - Parameter program: The program identifier to inspect.
    /// - Returns: The OpenGL program info log.
    private func programInfoLog(_ program: UInt32) -> String {
        var length: GLint = 0
        glad_glGetProgramiv(program, GLenum(GL_INFO_LOG_LENGTH), &length)
        guard length > 1 else { return "" }

        var buffer = [GLchar](repeating: 0, count: Int(length))
        glad_glGetProgramInfoLog(program, length, &length, &buffer)
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// A compiled OpenGL program that caches each requested uniform location.
@MainActor
final class GLProgram {
    /// The OpenGL program identifier.
    let identifier: UInt32

    /// The driver that created and manages the program.
    private let driver: any GLProgramDriver

    /// Uniform locations already looked up for this program.
    private var uniformLocations: [String: Int32] = [:]

    /// Creates a linked OpenGL program from GLSL source.
    /// - Parameters:
    ///   - vertexSource: GLSL source for the vertex shader.
    ///   - fragmentSource: GLSL source for the fragment shader.
    ///   - driver: The OpenGL program driver.
    /// - Throws: A `GLProgramError` if shader compilation or program linking fails.
    init(
        vertexSource: String,
        fragmentSource: String,
        driver: any GLProgramDriver = OpenGLProgramDriver()
    ) throws {
        identifier = try driver.compileProgram(vertexSource: vertexSource, fragmentSource: fragmentSource)
        self.driver = driver
    }

    /// Releases the linked OpenGL program on the main actor.
    isolated deinit {
        driver.deleteProgram(identifier)
    }

    /// Makes this program current for subsequent OpenGL drawing commands.
    func use() {
        driver.useProgram(identifier)
    }

    /// Returns a cached uniform location, querying the driver only the first time.
    /// - Parameter name: The uniform name.
    /// - Returns: The uniform location, or `-1` when it is not present.
    func uniformLocation(named name: String) -> Int32 {
        if let location = uniformLocations[name] {
            return location
        }

        let location = driver.uniformLocation(program: identifier, name: name)
        uniformLocations[name] = location
        return location
    }
}
