/// The built-in shader programs available to the rendering pipeline.
enum ShaderKind: Hashable, Sendable {
    /// The solid-color fill and stroke program.
    case solidColor

    /// The textured image program.
    case image

    /// The packaged resource directory for this shader kind.
    var resourceDirectory: String {
        switch self {
        case .solidColor:
            "default"
        case .image:
            "image"
        }
    }
}

/// Reuses one compiled program for each built-in shader kind.
@MainActor
final class GLShaderCache {
    /// The driver used when compiling new programs.
    private let driver: any GLProgramDriver

    /// Programs already compiled for their shader kinds.
    private var programs: [ShaderKind: GLProgram] = [:]

    /// Creates a shader cache backed by the supplied OpenGL driver.
    /// - Parameter driver: The driver used to compile and manage programs.
    init(driver: any GLProgramDriver = OpenGLProgramDriver()) {
        self.driver = driver
    }

    /// Returns the cached program for a shader kind, compiling it on first use.
    /// - Parameter kind: The built-in shader program to retrieve.
    /// - Returns: The shared compiled program for that kind.
    /// - Throws: A shader resource or compilation error when loading fails.
    func program(for kind: ShaderKind) throws -> GLProgram {
        if let program = programs[kind] {
            return program
        }

        let vertexSource = try CGShaderSource.load(directory: kind.resourceDirectory, fileName: "vertex")
        let fragmentSource = try CGShaderSource.load(directory: kind.resourceDirectory, fileName: "fragment")
        let program = try GLProgram(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            driver: driver
        )
        programs[kind] = program
        return program
    }
}
