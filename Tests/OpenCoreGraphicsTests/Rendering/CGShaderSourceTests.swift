import Testing
@testable import OpenCoreGraphics

/// Tests loading packaged shader sources and reporting missing files.
struct CGShaderSourceTests {
    /// Verifies every built-in shader is bundled and has a GLSL version.
    @Test(arguments: [
        (directory: "default", fileName: "vertex"),
        (directory: "default", fileName: "fragment"),
        (directory: "image", fileName: "vertex"),
        (directory: "image", fileName: "fragment"),
        (directory: "gradient", fileName: "vertex"),
        (directory: "gradient", fileName: "fragment"),
        (directory: "text", fileName: "vertex"),
        (directory: "text", fileName: "fragment")
    ])
    func packagedShaderContainsVersion(directory: String, fileName: String) throws {
        let source = try CGShaderSource.load(directory: directory, fileName: fileName)

        #expect(source.isEmpty == false)
        #expect(source.contains("#version 330 core"))
    }

    /// Verifies a missing packaged shader produces a typed resource error.
    @Test
    func missingShaderReportsTypedError() {
        #expect(throws: CGShaderSourceError.self) {
            try CGShaderSource.load(directory: "missing", fileName: "shader")
        }
    }
}
