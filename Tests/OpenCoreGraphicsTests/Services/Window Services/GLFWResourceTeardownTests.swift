import Testing
@testable import OpenCoreGraphics

/// Checks resource ownership and teardown order without a graphics driver.
@MainActor
struct GLFWResourceTeardownTests {
    /// Releases both windows in either order while another context is initially current.
    @Test(arguments: [false, true])
    func releasesEveryResourceOnceInItsOwningContext(reverse: Bool) throws {
        let a = try #require(OpaquePointer(bitPattern: 0xA1))
        let b = try #require(OpaquePointer(bitPattern: 0xB1))
        let state = ResourceTeardownState()
        state.current = reverse ? a : b
        let driver = GLFWContextDriver.injecting(
            { state.current },
            { state.current = $0 },
            { error in
                if error != .windowClosed {
                    Issue.record("Unexpected context selection failure")
                }
            }
        )
        let resourcesA = try ResourceBundle(state: state, owner: a)
        let resourcesB = try ResourceBundle(state: state, owner: b)
        let selectorA = GLFWContextSelector.make(a, driver)
        let selectorB = GLFWContextSelector.make(b, driver)
        let teardownA = makeTeardown(a, selectorA, driver, resourcesA, state)
        let teardownB = makeTeardown(b, selectorB, driver, resourcesB, state)
        let first = reverse ? teardownB : teardownA
        let second = reverse ? teardownA : teardownB
        let firstOwner = reverse ? b : a
        let secondOwner = reverse ? a : b

        #expect(first.attempt())
        #expect(state.current == secondOwner)
        #expect(first.attempt())
        #expect((reverse ? selectorB : selectorA).select() == .windowClosed)
        #expect(second.attempt())
        #expect(second.attempt())
        #expect(state.events.count == 8)
        #expect(Array(state.events.prefix(4)).allSatisfy { $0.owner == firstOwner })
        #expect(Array(state.events.suffix(4)).allSatisfy { $0.owner == secondOwner })
        for owner in [a, b] {
            #expect(state.events.filter { $0.owner == owner }.map(\.operation) ==
                    ["buffer", "texture", "program", "destroy"])
        }
    }

    /// Releases the programs created before shader or buffer initialization fails.
    @Test(arguments: [false, true])
    func partialRendererInitializationReleasesCreatedPrograms(bufferFailure: Bool) throws {
        let owner = try #require(OpaquePointer(bitPattern: 0xC1))
        let state = ResourceTeardownState()
        state.current = owner
        let driver = FailingProgramDriver(state: state, owner: owner, failCompilation: !bufferFailure)

        #expect(throws: (any Error).self) {
            try initializeFailingRenderer(driver: driver, state: state, owner: owner)
        }

        let expected = bufferFailure ? 4 : 2
        #expect(driver.created == expected)
        #expect(driver.deleted.sorted() == Array(1...UInt32(expected)))
        #expect(state.events.count == expected)
        #expect(state.events.allSatisfy { $0.owner == owner && $0.operation == "program" })
        let contextDriver = GLFWContextDriver.injecting(
            { state.current },
            { state.current = $0 },
            { _ in Issue.record("Unexpected context failure") }
        )
        let teardown = GLFWWindowTeardown(
            window: owner,
            contextSelector: GLFWContextSelector.make(owner, contextDriver),
            contextDriver: contextDriver,
            disableCallbacks: { _ in },
            destroyWindow: { window in
                #expect(state.current == window)
                state.events.append((window, "destroy"))
                state.current = nil
            },
            releasePlatform: {},
            releaseResources: {},
            recordFailure: { _ in Issue.record("Unexpected teardown failure") }
        )
        #expect(teardown.attempt())
        #expect(teardown.attempt())
        #expect(state.events.map(\.operation) == Array(repeating: "program", count: expected) + ["destroy"])
    }

    /// Restores the context saved before initialization, even if the new context is current.
    @Test
    func restoresContextSavedBeforePartialInitialization() throws {
        let a = try #require(OpaquePointer(bitPattern: 0xE1))
        let b = try #require(OpaquePointer(bitPattern: 0xE2))
        let state = ResourceTeardownState()
        state.current = a
        let driver = GLFWContextDriver.injecting(
            { state.current },
            { state.current = $0 },
            { _ in Issue.record("Unexpected context failure") }
        )
        let resources = try ResourceBundle(state: state, owner: a)
        let teardown = makeTeardown(a, GLFWContextSelector.make(a, driver), driver, resources, state)
        teardown.initializationRestoreContext = .some(b)

        #expect(teardown.attempt())
        #expect(state.current == b)
        #expect(state.events.map(\.operation) == ["buffer", "texture", "program", "destroy"])
        #expect(teardown.attempt())
        #expect(state.events.count == 4)
    }

    /// A later unrelated context replaces a stale restoration target after failed selection.
    @Test
    func retriesFailedSelectionWithoutRestoringStaleContext() throws {
        let a = try #require(OpaquePointer(bitPattern: 0xF1))
        let b = try #require(OpaquePointer(bitPattern: 0xF2))
        let c = try #require(OpaquePointer(bitPattern: 0xF3))
        let state = ResourceTeardownState()
        state.current = b
        var canSelectA = false
        var destroyed: Set<OpaquePointer> = []
        var selectedDestroyed: [OpaquePointer] = []
        let driver = GLFWContextDriver.injecting(
            { state.current },
            { context in
                if let context, destroyed.contains(context) { selectedDestroyed.append(context); return }
                if context == a && !canSelectA { return }
                state.current = context
            },
            { _ in }
        )
        let resourcesA = try ResourceBundle(state: state, owner: a)
        let resourcesB = try ResourceBundle(state: state, owner: b)
        let make: (OpaquePointer, ResourceBundle) -> GLFWWindowTeardown = { window, resources in
            GLFWWindowTeardown(
                window: window, contextSelector: GLFWContextSelector.make(window, driver),
                contextDriver: driver, disableCallbacks: { _ in },
                destroyWindow: { pointer in
                    #expect(state.current == pointer)
                    state.events.append((pointer, "destroy"))
                    destroyed.insert(pointer)
                    state.current = nil
                },
                releasePlatform: {}, releaseResources: { resources.release() },
                recordFailure: { state.failures.append($0) }
            )
        }
        let teardownA = make(a, resourcesA)
        let teardownB = make(b, resourcesB)
        let initialCount = GLFWWindowTeardownRegistry.pending.count
        GLFWWindowTeardownRegistry.perform(teardownA)
        GLFWWindowTeardownRegistry.retryPending()
        GLFWWindowTeardownRegistry.perform(teardownB)
        state.current = c
        canSelectA = true
        GLFWWindowTeardownRegistry.retryPending()
        GLFWWindowTeardownRegistry.retryPending()

        #expect(teardownA.isComplete)
        #expect(teardownB.isComplete)
        #expect(GLFWWindowTeardownRegistry.pending.count == initialCount)
        #expect(state.current == c)
        #expect(selectedDestroyed.isEmpty)
        #expect(state.events.filter { $0.owner == a }.map(\.operation) ==
                ["buffer", "texture", "program", "destroy"])
        #expect(state.events.filter { $0.owner == b }.map(\.operation) ==
                ["buffer", "texture", "program", "destroy"])
    }

    /// Supersedes a failed restoration when another live context is deliberately selected.
    @Test
    func preservesNewCurrentContextWhileBothTeardownsArePending() throws {
        let a = try #require(OpaquePointer(bitPattern: 0x101))
        let b = try #require(OpaquePointer(bitPattern: 0x102))
        let c = try #require(OpaquePointer(bitPattern: 0x103))
        let state = ResourceTeardownState()
        state.current = b
        var destroyed: Set<OpaquePointer> = []
        var selectedDestroyed: [OpaquePointer] = []
        var canRestoreB = false
        let driver = GLFWContextDriver.injecting(
            { state.current },
            { selected in
                if let selected, destroyed.contains(selected) {
                    selectedDestroyed.append(selected)
                    return
                }
                if selected == b && !canRestoreB { return }
                state.current = selected
            },
            { _ in }
        )
        let make: (OpaquePointer, ResourceBundle) -> GLFWWindowTeardown = { window, resources in
            GLFWWindowTeardown(
                window: window, contextSelector: GLFWContextSelector.make(window, driver),
                contextDriver: driver, disableCallbacks: { _ in },
                destroyWindow: { pointer in
                    #expect(state.current == pointer)
                    state.events.append((pointer, "destroy"))
                    destroyed.insert(pointer)
                    state.current = nil
                },
                releasePlatform: {}, releaseResources: { resources.release() },
                recordFailure: { state.failures.append($0) }
            )
        }
        let teardownA = make(a, try ResourceBundle(state: state, owner: a))
        let teardownB = make(b, try ResourceBundle(state: state, owner: b))
        let initialCount = GLFWWindowTeardownRegistry.pending.count
        GLFWWindowTeardownRegistry.perform(teardownA)
        GLFWWindowTeardownRegistry.retryPending()
        GLFWWindowTeardownRegistry.perform(teardownB)
        #expect(GLFWWindowTeardownRegistry.pending.count == initialCount + 2)
        #expect(destroyed == [a])
        #expect(teardownA.isComplete == false)
        #expect(teardownB.isComplete == false)

        state.current = c
        canRestoreB = true
        GLFWWindowTeardownRegistry.retryPending()
        GLFWWindowTeardownRegistry.retryPending()

        #expect(GLFWWindowTeardownRegistry.pending.count == initialCount)
        #expect(teardownA.isComplete)
        #expect(teardownB.isComplete)
        #expect(state.current == c)
        #expect(destroyed == [a, b])
        #expect(selectedDestroyed.isEmpty)
        for owner in [a, b] {
            #expect(state.events.filter { $0.owner == owner }.map(\.operation) ==
                    ["buffer", "texture", "program", "destroy"])
        }
    }

    /// Retries a failed restoration without repeating deletion or destroying its target early.
    @Test
    func retriesRestorationBeforeDestroyingThePreviousWindow() throws {
        let a = try #require(OpaquePointer(bitPattern: 0xD1))
        let b = try #require(OpaquePointer(bitPattern: 0xD2))
        let state = ResourceTeardownState()
        state.current = b
        var canRestore = false
        var failures: [GLFWContextSelectionError] = []
        let driver = GLFWContextDriver.injecting(
            { state.current },
            { context in
                if context == b && !canRestore { return }
                state.current = context
            },
            { failures.append($0) }
        )
        let resourcesA = try ResourceBundle(state: state, owner: a)
        let resourcesB = try ResourceBundle(state: state, owner: b)
        let selectorA = GLFWContextSelector.make(a, driver)
        let selectorB = GLFWContextSelector.make(b, driver)
        let teardownA = makeTeardown(a, selectorA, driver, resourcesA, state)
        let teardownB = makeTeardown(b, selectorB, driver, resourcesB, state)
        let initialCount = GLFWWindowTeardownRegistry.pending.count

        GLFWWindowTeardownRegistry.perform(teardownA)
        GLFWWindowTeardownRegistry.perform(teardownB)
        #expect(GLFWWindowTeardownRegistry.pending.count == initialCount + 2)
        #expect(state.events.map(\.operation) == ["buffer", "texture", "program", "destroy"])
        #expect(teardownA.isComplete == false)
        #expect(teardownB.isComplete == false)
        #expect(state.failures == [.selectionFailed])
        #expect(selectorA.select() == .windowClosed)
        #expect(selectorB.select() == .windowClosed)

        canRestore = true
        GLFWWindowTeardownRegistry.retryPending()
        #expect(GLFWWindowTeardownRegistry.pending.count == initialCount)
        #expect(teardownA.isComplete)
        #expect(teardownB.isComplete)
        #expect(state.events.map(\.operation) ==
                ["buffer", "texture", "program", "destroy", "buffer", "texture", "program", "destroy"])
        #expect(failures == [.windowClosed, .windowClosed])
    }

    /// Attempts renderer creation with a cache whose lifetime ends on failure.
    private func initializeFailingRenderer(
        driver: FailingProgramDriver,
        state: ResourceTeardownState,
        owner: OpaquePointer
    ) throws {
        let cache = GLShaderCache(driver: driver)
        _ = try GLRenderer(
            shaderCache: cache,
            batchBufferDriver: FailingBufferDriver(state: state, owner: owner)
        )
    }

    /// Creates a teardown around fake resources whose releases check the selected context.
    private func makeTeardown(
        _ window: OpaquePointer,
        _ selector: GLFWContextSelector,
        _ driver: GLFWContextDriver,
        _ resources: ResourceBundle,
        _ state: ResourceTeardownState
    ) -> GLFWWindowTeardown {
        GLFWWindowTeardown(
            window: window,
            contextSelector: selector,
            contextDriver: driver,
            disableCallbacks: { _ in },
            destroyWindow: { owner in
                #expect(state.current == owner)
                state.events.append((owner, "destroy"))
                state.current = nil
            },
            releasePlatform: {},
            releaseResources: { resources.release() },
            recordFailure: { state.failures.append($0) }
        )
    }
}

/// Fails buffer allocation after shader creation.
@MainActor
private struct FailingBufferDriver: GLBatchBufferDriver {
    /// Shared fake context and event log.
    let state: ResourceTeardownState
    /// The context for the attempted allocation.
    let owner: OpaquePointer
    /// Reports an allocation failure.
    func createBuffers() throws -> (vertexArray: UInt32, vertexBuffer: UInt32) {
        #expect(state.current == owner)
        throw GLBatchBufferError.bufferCreationFailed
    }
    /// Ignores unused vertex uploads.
    func upload(vertices: [Float], vertexArray: UInt32, vertexBuffer: UInt32) {}
    /// Ignores unused draw requests.
    func draw(vertexCount: Int, state: GLBatchState) {}
    /// Reports unexpected deletion when allocation failed.
    func deleteBuffers(vertexArray: UInt32, vertexBuffer: UInt32) {
        Issue.record("No buffer was allocated")
    }
}

/// Creates programs until the requested initialization failure.
@MainActor
private final class FailingProgramDriver: GLProgramDriver {
    /// Shared fake context and event log.
    let state: ResourceTeardownState
    /// The context that owns each created program.
    let owner: OpaquePointer
    /// Whether the third compilation should fail.
    let failCompilation: Bool
    /// The number of programs successfully created.
    var created = 0
    /// The identifiers deleted by the renderer's partial initialization.
    var deleted: [UInt32] = []

    /// Creates a driver for the selected failure point.
    init(state: ResourceTeardownState, owner: OpaquePointer, failCompilation: Bool) {
        self.state = state
        self.owner = owner
        self.failCompilation = failCompilation
    }
    /// Returns unique fake identifiers until the configured failure.
    func compileProgram(vertexSource: String, fragmentSource: String) throws -> UInt32 {
        #expect(state.current == owner)
        if failCompilation && created == 2 { throw GLProgramError.programCreationFailed }
        created += 1
        return UInt32(created)
    }
    /// Returns an unused uniform location.
    func uniformLocation(program: UInt32, name: String) -> Int32 { -1 }
    /// Ignores unused program activation.
    func useProgram(_ program: UInt32) {}
    /// Records deletion of a successfully created program.
    func deleteProgram(_ program: UInt32) {
        #expect(state.current == owner)
        deleted.append(program)
        state.events.append((owner, "program"))
    }
}

/// Tracks the fake current context and the operations issued for each owner.
@MainActor
private final class ResourceTeardownState {
    /// The context selected by the fake driver.
    var current: OpaquePointer?
    /// The recorded resource releases and window destructions.
    var events: [(owner: OpaquePointer, operation: String)] = []
    /// The teardown failures reported by the fake driver.
    var failures: [GLFWContextSelectionError] = []
}

/// Owns representative real wrappers backed by fake resource drivers.
@MainActor
private final class ResourceBundle {
    /// The batch buffer wrapper.
    private var buffer: GLBatchBuffer?
    /// The texture wrapper.
    private var texture: GLTexture?
    /// The linked program wrapper.
    private var program: GLProgram?

    /// Creates resources that record their release context.
    init(state: ResourceTeardownState, owner: OpaquePointer) throws {
        buffer = try GLBatchBuffer(driver: ResourceBufferDriver(state: state, owner: owner))
        texture = GLTexture(identifier: 2, release: { _ in
            #expect(state.current == owner)
            state.events.append((owner, "texture"))
        })
        program = try GLProgram(
            vertexSource: "",
            fragmentSource: "",
            driver: ResourceProgramDriver(state: state, owner: owner)
        )
    }

    /// Drops each wrapper exactly once while its context is selected.
    func release() {
        buffer = nil
        texture = nil
        program = nil
    }
}

/// Simulates buffer allocation and deletion for one owning context.
@MainActor
private struct ResourceBufferDriver: GLBatchBufferDriver {
    /// Shared fake context and event log.
    let state: ResourceTeardownState
    /// The context that owns the allocated buffer.
    let owner: OpaquePointer

    /// Returns fake vertex array and buffer identifiers.
    func createBuffers() throws -> (vertexArray: UInt32, vertexBuffer: UInt32) { (1, 2) }
    /// Ignores vertex uploads in this lifecycle test.
    func upload(vertices: [Float], vertexArray: UInt32, vertexBuffer: UInt32) {}
    /// Ignores draw requests in this lifecycle test.
    func draw(vertexCount: Int, state: GLBatchState) {}
    /// Records deletion in the currently selected context.
    func deleteBuffers(vertexArray: UInt32, vertexBuffer: UInt32) {
        #expect(state.current == owner)
        state.events.append((owner, "buffer"))
    }
}

/// Simulates program creation and deletion for one owning context.
@MainActor
private struct ResourceProgramDriver: GLProgramDriver {
    /// Shared fake context and event log.
    let state: ResourceTeardownState
    /// The context that owns the program.
    let owner: OpaquePointer

    /// Returns a fake linked program identifier.
    func compileProgram(vertexSource: String, fragmentSource: String) throws -> UInt32 { 3 }
    /// Returns an unused uniform location.
    func uniformLocation(program: UInt32, name: String) -> Int32 { -1 }
    /// Ignores program activation in this lifecycle test.
    func useProgram(_ program: UInt32) {}
    /// Records program deletion in the currently selected context.
    func deleteProgram(_ program: UInt32) {
        #expect(state.current == owner)
        state.events.append((owner, "program"))
    }
}
