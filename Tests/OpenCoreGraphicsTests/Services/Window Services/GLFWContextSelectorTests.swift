import Foundation
import Testing
import OpenGLFW
@testable import OpenCoreGraphics

/// Tests injectable context selection and closed-window behavior without a GL context.
@MainActor
struct GLFWContextSelectorTests {
    /// Verifies selecting alternating windows always makes the requested context current.
    @Test
    func selectsEachRequestedContextWithoutRestoringPreviousContext() throws {
        let contextA = try #require(OpaquePointer(bitPattern: 0xA))
        let contextB = try #require(OpaquePointer(bitPattern: 0xB))
        var currentContext: OpaquePointer?
        var selections: [(previous: OpaquePointer?, selected: OpaquePointer?)] = []
        let driver = GLFWContextDriver.injecting(
            { currentContext },
            { selectedContext in
                selections.append((currentContext, selectedContext))
                currentContext = selectedContext
            },
            { _ in }
        )
        let selectorA = GLFWContextSelector.make(contextA, driver)
        let selectorB = GLFWContextSelector.make(contextB, driver)

        #expect(selectorA.select() == nil)
        #expect(selectorB.select() == nil)
        #expect(selectorA.select() == nil)

        #expect(selections.count == 3)
        #expect(selections[0].previous == nil)
        #expect(selections[0].selected == contextA)
        #expect(selections[1].previous == contextA)
        #expect(selections[1].selected == contextB)
        #expect(selections[2].previous == contextB)
        #expect(selections[2].selected == contextA)
        #expect(currentContext == contextA)
    }

    /// Verifies a closed window never reaches the driver and reports a typed failure.
    @Test
    func selectionAfterClosingWindowFailsExplicitly() throws {
        let context = try #require(OpaquePointer(bitPattern: 0xC))
        var currentContext: OpaquePointer?
        var selections: [OpaquePointer?] = []
        var failures: [GLFWContextSelectionError] = []
        let driver = GLFWContextDriver.injecting(
            { currentContext },
            { selectedContext in
                selections.append(selectedContext)
                currentContext = selectedContext
            },
            { failures.append($0) }
        )
        let selector = GLFWContextSelector.make(context, driver)

        #expect(selector.select() == nil)
        selector.close()
        let selectionFailure = selector.select()

        #expect(selections == [context])
        #expect(failures == [.windowClosed])
        #expect(selectionFailure == .windowClosed)
        #expect(currentContext == context)
    }

    /// Verifies a failed driver selection is surfaced instead of reporting success.
    @Test
    func reportsWhenDriverDoesNotSelectRequestedContext() throws {
        let context = try #require(OpaquePointer(bitPattern: 0xD))
        let currentContext: OpaquePointer? = nil
        var failures: [GLFWContextSelectionError] = []
        let driver = GLFWContextDriver.injecting(
            { currentContext },
            { _ in },
            { failures.append($0) }
        )
        let selector = GLFWContextSelector.make(context, driver)

        let selectionFailure = selector.select()

        #expect(failures == [.selectionFailed])
        #expect(selectionFailure == .selectionFailed)
        #expect(currentContext == nil)
    }

    /// Verifies GLFW's invalid-size failures release the retain acquired before window creation.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_GL_COMPARISON"] == "1"))
    func failedWindowCreationReleasesPlatformRetain() throws {
        let platform = GLFWPlatform.shared
        let initialCount = try #require(Mirror(reflecting: platform).descendant("referenceCount") as? Int)

        for _ in 0..<2 {
            #expect(throws: CGWindowError.windowCreationFailed) {
                try CGWindow(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
            }
            let currentCount = try #require(Mirror(reflecting: platform).descendant("referenceCount") as? Int)
            #expect(currentCount == initialCount)
        }
    }

    /// Verifies the final retain is released only after restoring a previously nil context.
    @Test
    func restoresNilContextBeforeTerminatingLastPlatformRetain() throws {
        let window = try #require(OpaquePointer(bitPattern: 0x11))
        let state = GLFWTeardownPlatformDriver()
        let platform = GLFWPlatform(driver: state)
        try #require(platform.retain())
        var currentContext: OpaquePointer?
        let driver = GLFWContextDriver.injecting(
            {
                #expect(state.isInitialized)
                state.events.append("getContext")
                return currentContext
            },
            { context in
                #expect(state.isInitialized)
                state.events.append(context == nil ? "restoreNil" : "selectWindow")
                currentContext = context
            },
            { _ in Issue.record("Unexpected context failure") }
        )
        let teardown = GLFWWindowTeardown(
            window: window,
            contextSelector: GLFWContextSelector.make(window, driver),
            contextDriver: driver,
            disableCallbacks: { _ in state.events.append("disableCallbacks") },
            destroyWindow: { _ in
                #expect(state.isInitialized)
                state.events.append("destroyWindow")
                currentContext = nil
            },
            releasePlatform: { platform.release() },
            releaseResources: { state.events.append("releaseResources") },
            recordFailure: { _ in Issue.record("Unexpected teardown failure") }
        )

        #expect(teardown.attempt())
        #expect(state.events == [
            "initialize", "disableCallbacks", "getContext", "selectWindow", "getContext",
            "releaseResources", "destroyWindow", "restoreNil", "getContext", "terminate"
        ])
        #expect(currentContext == nil)
        #expect(state.isInitialized == false)
        #expect(teardown.attempt())
        #expect(state.events.last == "terminate")
    }

    /// Verifies the system GLFW driver and a window-owned target after the GLFW window is destroyed.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_GL_COMPARISON"] == "1"))
    func realGLFWWindowRejectsTargetFlushAfterDestruction() throws {
        try #require(GLFWPlatform.shared.retain())
        defer { GLFWPlatform.shared.release() }

        glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_API)
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3)
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3)
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE)
        glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE)
        let context = try #require(
            glfwCreateWindow(32, 32, "Context lifecycle test", nil, nil)
        )
        let selector = GLFWContextSelector.make(context, .system)
        #expect(selector.select() == nil)
        #expect(glfwGetCurrentContext() == context)

        let renderer = RecordingWindowRenderBackend()
        let target = WindowRenderTarget(size: CGSize(width: 32, height: 32), renderer: renderer)
        target.contextSelector = selector
        target.submit(.resetClip)

        selector.close()
        glfwDestroyWindow(context)
        target.flush()

        #expect(renderer.executionCount == 0)
        #expect(target.contextError == .windowClosed)
    }

    /// Verifies failed teardown detaches callbacks, blocks context use, retains resources, and retries.
    @Test
    func failedTeardownDetachesCallbacksAndRecoversWithoutReleasingInWrongContext() throws {
        let contextA = try #require(OpaquePointer(bitPattern: 0xF))
        let contextB = try #require(OpaquePointer(bitPattern: 0x10))
        let state = GLFWTeardownTestState(currentContext: contextB)
        let weakResource = GLFWWeakResourceHolder(state.retainedResource)
        let driver = GLFWContextDriver.injecting(
            { state.currentContext },
            { selectedContext in
                state.events.append("select")
                if selectedContext == contextA, !state.canSelectA { return }
                state.currentContext = selectedContext
            },
            { state.failures.append($0) }
        )
        let selector = GLFWContextSelector.make(contextA, driver)
        let pendingCount = GLFWWindowTeardownRegistry.pending.count
        let teardown = GLFWWindowTeardown(
            window: contextA,
            contextSelector: selector,
            contextDriver: driver,
            disableCallbacks: { window in
                #expect(window == contextA)
                state.events.append("disableCallbacks")
                state.callbacksAreActive = false
            },
            destroyWindow: { window in
                #expect(window == contextA)
                state.events.append("destroyWindow")
                state.destroyedWindow = true
            },
            releasePlatform: {
                state.events.append("releasePlatform")
                state.releasedPlatform = true
            },
            releaseResources: {
                state.events.append("releaseResources")
                state.resourceIsAlive = false
                state.retainedResource = nil
            },
            recordFailure: { state.failures.append($0) }
        )

        GLFWWindowTeardownRegistry.perform(teardown)
        if state.callbacksAreActive {
            state.deliveredEventCount += 1
        }

        #expect(GLFWWindowTeardownRegistry.pending.count == pendingCount + 1)
        #expect(state.events.prefix(2) == ["disableCallbacks", "select"])
        #expect(state.callbacksAreActive == false)
        #expect(state.deliveredEventCount == 0)
        #expect(selector.select() == .windowClosed)
        #expect(state.resourceIsAlive)
        #expect(weakResource.resource != nil)
        #expect(state.destroyedWindow == false)
        #expect(state.releasedPlatform == false)
        #expect(state.failures.contains(.selectionFailed))
        #expect(state.failures.contains(.windowClosed))

        state.canSelectA = true
        GLFWWindowTeardownRegistry.retryPending()
        if state.callbacksAreActive {
            state.deliveredEventCount += 1
        }

        #expect(GLFWWindowTeardownRegistry.pending.count == pendingCount)
        #expect(state.events.suffix(5) == [
            "select",
            "releaseResources",
            "destroyWindow",
            "select",
            "releasePlatform"
        ])
        #expect(state.resourceIsAlive == false)
        #expect(weakResource.resource == nil)
        #expect(state.destroyedWindow)
        #expect(state.releasedPlatform)
        #expect(state.deliveredEventCount == 0)
        #expect(state.currentContext == contextB)
        #expect(teardown.isComplete)
    }

}

/// Simulates an initialized GLFW platform and records its final termination.
@MainActor
private final class GLFWTeardownPlatformDriver: GLFWPlatformDriver {
    /// Whether GLFW is currently initialized.
    var isInitialized = false

    /// Platform and context operations observed in order.
    var events: [String] = []

    /// Initializes the simulated platform.
    func initialize() -> Bool {
        isInitialized = true
        events.append("initialize")
        return true
    }

    /// Records termination of the simulated platform.
    func terminate() {
        events.append("terminate")
        isInitialized = false
    }
}

/// Holds mutable fake GLFW state for the injected failed-teardown test.
@MainActor
private final class GLFWTeardownTestState {
    /// The currently selected fake GLFW context.
    var currentContext: OpaquePointer?

    /// Whether the next attempt to select context A succeeds.
    var canSelectA = false

    /// Indicates whether fake GLFW callbacks remain installed.
    var callbacksAreActive = true

    /// Counts events delivered through still-active fake callbacks.
    var deliveredEventCount = 0

    /// Indicates whether test GL resources are still retained.
    var resourceIsAlive = true

    /// A reference token proving failed teardown keeps resources alive until a safe retry.
    var retainedResource: GLFWTeardownTestResource? = GLFWTeardownTestResource()

    /// Indicates whether the fake GLFW window was destroyed.
    var destroyedWindow = false

    /// Indicates whether the transferred GLFW platform reference was released.
    var releasedPlatform = false

    /// Records callback, selection, resource, and window operations.
    var events: [String] = []

    /// Records typed failures from selection and teardown.
    var failures: [GLFWContextSelectionError] = []

    /// Creates the fake state with the initially current context.
    /// - Parameter currentContext: The context selected before the failed teardown.
    init(currentContext: OpaquePointer?) {
        self.currentContext = currentContext
    }
}

/// A reference token used to verify ownership across failed teardown retries.
private final class GLFWTeardownTestResource { }

/// Observes whether a failed teardown continues to retain its resource token.
@MainActor
private final class GLFWWeakResourceHolder {
    /// The resource while another owner keeps it alive.
    weak var resource: GLFWTeardownTestResource?

    /// Creates a weak observer for the supplied resource.
    /// - Parameter resource: The resource whose lifetime is observed.
    init(_ resource: GLFWTeardownTestResource?) {
        self.resource = resource
    }
}

/// Counts render submissions made while verifying real GLFW lifecycle protection.
private final class RecordingWindowRenderBackend: CGRenderBackend {
    /// The number of render submissions received.
    private(set) var executionCount = 0

    /// Records a render submission without issuing OpenGL commands.
    /// - Parameters:
    ///   - commands: The drawing operations submitted for rendering.
    ///   - size: The render destination dimensions.
    func execute(_ commands: [DrawCommand], size: OpenCoreGraphics.CGSize) {
        executionCount += 1
    }
}
