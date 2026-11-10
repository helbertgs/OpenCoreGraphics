import Foundation
import OpenGLFW

/// A failure raised when a GLFW window context cannot be selected.
enum GLFWContextSelectionError: Error, Equatable, Sendable {
    /// The window owning the context has already been closed.
    case windowClosed

    /// GLFW did not make the requested context current.
    case selectionFailed
}

/// Stores the window identity and close state shared by a selector's operations.
@MainActor
private final class GLFWWindowContextState {
    /// The GLFW window that owns the context.
    let window: OpaquePointer

    /// Indicates whether the owning GLFW window has been destroyed.
    var isClosed = false

    /// Creates state for the GLFW window that owns the context.
    /// - Parameter window: The GLFW window whose context is being selected.
    private init(window: OpaquePointer) {
        self.window = window
    }

    /// Creates state while keeping its initializer private to this implementation.
    static let make: (OpaquePointer) -> GLFWWindowContextState = { window in
        GLFWWindowContextState(window: window)
    }
}

/// Supplies GLFW context operations so selection can be tested without a display.
@MainActor
struct GLFWContextDriver {
    /// Returns the context currently selected on the calling thread.
    let currentContext: @MainActor () -> OpaquePointer?

    /// Selects the supplied context on the calling thread.
    let makeContextCurrent: @MainActor (OpaquePointer?) -> Void

    /// Records a context-selection failure for diagnostics or tests.
    let recordFailure: @MainActor (GLFWContextSelectionError) -> Void

    /// Creates a driver from injectable context operations and failure recording.
    static let injecting: (
        @escaping @MainActor () -> OpaquePointer?,
        @escaping @MainActor (OpaquePointer?) -> Void,
        @escaping @MainActor (GLFWContextSelectionError) -> Void
    ) -> GLFWContextDriver = { currentContext, makeContextCurrent, recordFailure in
        GLFWContextDriver(
            currentContext: currentContext,
            makeContextCurrent: makeContextCurrent,
            recordFailure: recordFailure
        )
    }

    /// Connects context selection to GLFW's system functions.
    static let system = GLFWContextDriver(
        currentContext: { glfwGetCurrentContext() },
        makeContextCurrent: { glfwMakeContextCurrent($0) },
        recordFailure: { error in
            NSLog("OpenCoreGraphics GLFW context selection failed: %@", String(describing: error))
        }
    )
}

/// Selects one window's context without restoring the context that was current before selection.
@MainActor
struct GLFWContextSelector {
    /// Selects the owning window's context and leaves it current, or throws after closure.
    let select: @MainActor () -> GLFWContextSelectionError?

    /// Validates that the owning window still exists without changing the current context.
    let ensureOpen: @MainActor () -> GLFWContextSelectionError?

    /// Marks the context closed so later selections fail without changing the current context.
    let close: @MainActor () -> Void

    /// Creates a selector for a window using the supplied context driver.
    static let make: (
        OpaquePointer,
        GLFWContextDriver
    ) -> GLFWContextSelector = { window, driver in
        let state = GLFWWindowContextState.make(window)

        return GLFWContextSelector(
            select: {
                guard !state.isClosed else {
                    driver.recordFailure(.windowClosed)
                    return .windowClosed
                }

                driver.makeContextCurrent(state.window)
                guard driver.currentContext() == state.window else {
                    driver.recordFailure(.selectionFailed)
                    return .selectionFailed
                }

                return nil
            },
            ensureOpen: {
                guard !state.isClosed else {
                    driver.recordFailure(.windowClosed)
                    return .windowClosed
                }

                return nil
            },
            close: {
                state.isClosed = true
            }
        )
    }
}
