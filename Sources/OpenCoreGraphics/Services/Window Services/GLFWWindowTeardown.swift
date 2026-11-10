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

    /// Indicates the window was destroyed and only context restoration remains.
    private var windowWasDestroyed = false

    /// The previous context that must be restored before completing teardown.
    private var restorationTarget: OpaquePointer?

    /// Overrides the context to restore when initialization selected the new window earlier.
    var initializationRestoreContext: OpaquePointer??

    /// Indicates the original context has been captured for all subsequent retries.
    private var hasRestorationTarget = false

    /// The observed current context after a failed restoration attempt.
    private var contextAfterFailedRestoration: OpaquePointer?

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

    /// Disables ordinary GL use and releases resources in their owning context.
    /// A failed restoration remains pending without deleting the resources or window again.
    /// - Returns: `true` when the resources, GLFW window, and platform retain are released.
    @discardableResult
    func attempt() -> Bool {
        guard !isComplete else { return true }

        if windowWasDestroyed {
            return finishRestoration()
        }

        if !isPrepared {
            disableCallbacks(window)
            contextSelector.close()
            isPrepared = true
        }

        guard !GLFWWindowTeardownRegistry.pending.contains(where: {
            $0 !== self && !$0.isComplete && $0.windowWasDestroyed && $0.restorationTarget == window
        }) else { return false }

        if !hasRestorationTarget {
            restorationTarget = initializationRestoreContext ?? contextDriver.currentContext()
            hasRestorationTarget = true
        }
        let previousContext = restorationTarget
        contextDriver.makeContextCurrent(window)
        guard contextDriver.currentContext() == window else {
            recordFailure(.selectionFailed)
            if contextDriver.currentContext() != previousContext {
                contextDriver.makeContextCurrent(previousContext)
                if contextDriver.currentContext() != previousContext {
                    recordFailure(.selectionFailed)
                }
            }
            hasRestorationTarget = false
            initializationRestoreContext = nil
            return false
        }

        releaseResources?()
        releaseResources = nil
        destroyWindow(window)

        if previousContext != window {
            windowWasDestroyed = true
            contextAfterFailedRestoration = contextDriver.currentContext()
            return finishRestoration()
        }

        releasePlatform()
        isComplete = true
        return true
    }

    /// Retries restoration without touching the already-destroyed window or its resources.
    private func finishRestoration() -> Bool {
        let currentContext = contextDriver.currentContext()
        if currentContext != contextAfterFailedRestoration {
            releasePlatform()
            isComplete = true
            return true
        }
        contextDriver.makeContextCurrent(restorationTarget)
        guard contextDriver.currentContext() == restorationTarget else {
            contextAfterFailedRestoration = contextDriver.currentContext()
            recordFailure(.selectionFailed)
            return false
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

    /// Retries retained teardowns without destroying a context still awaiting restoration.
    static func retryPending() {
        guard !pending.isEmpty else { return }
        let queuedTeardowns = pending
        for teardown in queuedTeardowns {
            _ = teardown.attempt()
        }
        pending.removeAll { $0.isComplete }
    }
}
