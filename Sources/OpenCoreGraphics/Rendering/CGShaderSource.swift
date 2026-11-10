import Foundation

/// An error raised while locating a packaged shader resource.
enum CGShaderSourceError: Error, Equatable, Sendable {
    /// The named shader file is not present in the requested resource directory.
    case resourceNotFound(String)
}

/// Loads GLSL source files bundled with the OpenCoreGraphics target.
enum CGShaderSource {
    /// Reads a shader file from a directory under the packaged Resources folder.
    /// - Parameters:
    ///   - directory: The shader subdirectory, such as `default` or `image`.
    ///   - fileName: The shader file name without its `.glsl` extension.
    /// - Returns: The UTF-8 shader source.
    /// - Throws: `CGShaderSourceError.resourceNotFound` if the resource is missing.
    static func load(directory: String, fileName: String) throws -> String {
        let resourcePath = "Resources/\(directory)/\(fileName).glsl"
        guard let url = Bundle.module.url(
            forResource: fileName,
            withExtension: "glsl",
            subdirectory: "Resources/\(directory)"
        ) else {
            throw CGShaderSourceError.resourceNotFound(resourcePath)
        }

        return try String(contentsOf: url, encoding: .utf8)
    }
}
