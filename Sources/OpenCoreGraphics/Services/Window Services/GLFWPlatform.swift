import OpenGLFW

/// A driver that initializes and terminates the GLFW library.
@MainActor
protocol GLFWPlatformDriver {
    /// Initializes GLFW and reports whether initialization succeeded.
    func initialize() -> Bool

    /// Terminates the GLFW library.
    func terminate()
}

/// Coordinates GLFW initialization for all windows in the process.
@MainActor
final class GLFWPlatform {
    /// The process-wide platform instance used by windows.
    static let shared = GLFWPlatform(driver: GLFWSystemDriver())

    /// The driver responsible for GLFW library operations.
    private let driver: any GLFWPlatformDriver

    /// The number of active owners of the initialized GLFW library.
    private var referenceCount = 0

    /// Creates a platform coordinator with the supplied GLFW driver.
    /// - Parameter driver: The driver used to initialize and terminate GLFW.
    init(driver: any GLFWPlatformDriver) {
        self.driver = driver
    }

    /// Retains the GLFW library, initializing it for the first active owner.
    /// - Returns: `true` when the platform is initialized and retained.
    @discardableResult
    func retain() -> Bool {
        if referenceCount == 0, !driver.initialize() {
            return false
        }

        referenceCount += 1
        return true
    }

    /// Releases one owner and terminates GLFW when the last owner is released.
    func release() {
        guard referenceCount > 0 else { return }

        referenceCount -= 1
        if referenceCount == 0 {
            driver.terminate()
        }
    }
}

/// Connects the platform coordinator to GLFW's process-level functions.
@MainActor
private struct GLFWSystemDriver: GLFWPlatformDriver {
    /// Initializes the GLFW library.
    /// - Returns: `true` when GLFW initialization succeeds.
    func initialize() -> Bool {
        glfwInit() != GLFW_FALSE
    }

    /// Terminates the GLFW library.
    func terminate() {
        glfwTerminate()
    }
}
