/// An error that can occur while creating an OpenGL window.
public enum CGWindowError: Error, Equatable, Sendable {
    /// GLFW could not be initialized.
    case glfwInitFailed

    /// GLFW could not create the requested window.
    case windowCreationFailed

    /// OpenGL function loading failed after GLFW created the window.
    case gladLoadFailed
}
