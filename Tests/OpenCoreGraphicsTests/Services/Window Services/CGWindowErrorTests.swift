import Testing
@testable import OpenCoreGraphics

/// Tests the typed failures exposed by window creation.
struct CGWindowErrorTests {
    /// Verifies each window creation failure has a distinct error value.
    @Test
    func creationErrorsAreDistinct() {
        let errors: [CGWindowError] = [
            .glfwInitFailed,
            .windowCreationFailed,
            .gladLoadFailed
        ]

        #expect(Set(errors).count == 3)
    }
}
