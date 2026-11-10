import Foundation

/// Coordinates a framebuffer resize while the owning window's context is current.
@MainActor
struct GLFWFramebufferResize {
    /// Selects the owner, drains old-size work, then updates the viewport and window state.
    static let apply: (
        GLFWContextSelector,
        Int32,
        Int32,
        @MainActor () -> Bool,
        @MainActor (Int32, Int32) -> Void,
        @MainActor (Int32, Int32) -> Void
    ) -> Bool = { selector, width, height, flushPending, updateViewport, updateState in
        guard selector.select() == nil, flushPending() else { return false }
        updateViewport(width, height)
        updateState(width, height)
        return true
    }
}
