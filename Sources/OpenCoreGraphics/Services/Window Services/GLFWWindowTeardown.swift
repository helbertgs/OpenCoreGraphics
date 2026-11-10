import OpenGLFW

/// Performs and, when needed, retries safe teardown of one GLFW window's GL resources.
@MainActor
final class GLFWWindowTeardown {
    /// The GLFW window that owns the retained context.
    let window: OpaquePointer

    /// The selector closed to prevent normal rendering through the retained context.
    private let contextSelector: GLFWContextSelector

    /// The context operations used to select and verify the owning context.
    private let contextDriver: GLFWContextDriver

    /// Removes all callbacks and the GLFW user pointer before this owner can disappear.
    private let disableCallbacks: @MainActor (OpaquePointer) -> Void

    /// Destroys the GLFW window after its GL resources have been released.
    private let destroyWindow: @MainActor (OpaquePointer) -> Void

    /// Releases the GLFW platform retain transferred by the owning window.
    private let releasePlatform: @MainActor () -> Void

    /// Releases the GL renderer only after its owning context becomes current.
    private var releaseResources: (@MainActor () -> Void)?

    /// Records typed context-selection failures.
    private let recordFailure: @MainActor (GLFWContextSelectionError) -> Void

    /// Indicates callbacks have been detached and normal context use has been disabled.
    private var isPrepared = false

    /// Indicates the renderer and GLFW window have both been released.
    private(set) var isComplete = false

    /// Creates a teardown operation with injectable GLFW and resource operations.
    /// - Parameters:
    ///   - window: The GLFW window that owns the GL resources.
    ///   - contextSelector: The normal-use selector to close before teardown.
    ///   - contextDriver: The GLFW context operations used for retries.
    ///   - disableCallbacks: An operation that removes callbacks and the window user pointer.
    ///   - destroyWindow: An operation that destroys the GLFW window.
    ///   - releasePlatform: An operation that releases the window's GLFW retain.
    ///   - releaseResources: An operation that releases GL objects in their owning context.
    init(
        window: OpaquePointer,
        contextSelector: GLFWContextSelector,
        contextDriver: GLFWContextDriver,
        disableCallbacks: @escaping @MainActor (OpaquePointer) -> Void,
        destroyWindow: @escaping @MainActor (OpaquePointer) -> Void,
        releasePlatform: @escaping @MainActor () -> Void,
        releaseResources: @escaping @MainActor () -> Void,
        recordFailure: @escaping @MainActor (GLFWContextSelectionError) -> Void
    ) {
        self.window = window
        self.contextSelector = contextSelector
        self.contextDriver = contextDriver
        self.disableCallbacks = disableCallbacks
        self.destroyWindow = destroyWindow
        self.releasePlatform = releasePlatform
        self.releaseResources = releaseResources
        self.recordFailure = recordFailure
    }

    /// Disables callbacks and ordinary GL use, then releases resources if selection succeeds.
    /// - Returns: `true` when the resources, GLFW window, and platform retain are released.
    @discardableResult
    func attempt() -> Bool {
        guard !isComplete else { return true }

        if !isPrepared {
            disableCallbacks(window)
            contextSelector.close()
            isPrepared = true
        }

        let previousContext = contextDriver.currentContext()
        contextDriver.makeContextCurrent(window)
        guard contextDriver.currentContext() == window else {
            recordFailure(.selectionFailed)
            if contextDriver.currentContext() != previousContext {
                contextDriver.makeContextCurrent(previousContext)
            }
            return false
        }

        releaseResources?()
        releaseResources = nil
        destroyWindow(window)

        if previousContext != window {
            contextDriver.makeContextCurrent(previousContext)
            if contextDriver.currentContext() != previousContext {
                recordFailure(.selectionFailed)
            }
        }

        releasePlatform()
        isComplete = true
        return true
    }
}

/// Retains failed teardowns and retries them before creating another GLFW window.
@MainActor
enum GLFWWindowTeardownRegistry {
    /// Teardowns whose owning contexts could not yet be selected.
    private(set) static var pending: [GLFWWindowTeardown] = []

    /// Destroys a GLFW window after its owning renderer has been deinitialized.
    static var destroyWindow: @MainActor (OpaquePointer) -> Void = { glfwDestroyWindow($0) }

    /// Removes callbacks and the GLFW user pointer before a window owner can disappear.
    static let disableCallbacks: @MainActor (OpaquePointer) -> Void = { window in
        glfwSetFramebufferSizeCallback(window, nil)
        glfwSetKeyCallback(window, nil)
        glfwSetCursorPosCallback(window, nil)
        glfwSetMouseButtonCallback(window, nil)
        glfwSetWindowSizeCallback(window, nil)
        glfwSetWindowUserPointer(window, nil)
    }

    /// Attempts teardown immediately and retains incomplete work for a later retry.
    /// - Parameter teardown: The window teardown to perform.
    static func perform(_ teardown: GLFWWindowTeardown) {
        guard !teardown.attempt() else { return }
        pending.append(teardown)
    }

    /// Retries retained teardowns, preserving whichever unrelated context was current.
    static func retryPending() {
        guard !pending.isEmpty else { return }
        let queuedTeardowns = pending
        pending.removeAll(keepingCapacity: true)

        for teardown in queuedTeardowns where !teardown.attempt() {
            pending.append(teardown)
        }
    }
}
