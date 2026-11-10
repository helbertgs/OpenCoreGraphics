import Testing
@testable import OpenCoreGraphics

/// Tests reference counting and initialization failure handling for GLFW.
@MainActor
struct GLFWPlatformTests {
    /// Verifies GLFW initializes once and terminates after the final release.
    @Test
    func initializesOnceForMultipleOwners() {
        let driver = RecordingGLFWPlatformDriver()
        let platform = GLFWPlatform(driver: driver)

        #expect(platform.retain())
        #expect(platform.retain())
        #expect(driver.initializeCount == 1)

        platform.release()
        #expect(driver.terminateCount == 0)

        platform.release()
        #expect(driver.terminateCount == 1)

        platform.release()
        #expect(driver.terminateCount == 1)

        #expect(platform.retain())
        #expect(driver.initializeCount == 2)
        platform.release()
        #expect(driver.terminateCount == 2)
    }

    /// Verifies failed initialization is not retained and can be retried.
    @Test
    func failedInitializationDoesNotRetainPlatform() {
        let driver = RecordingGLFWPlatformDriver()
        driver.initializationSucceeds = false
        let platform = GLFWPlatform(driver: driver)

        #expect(platform.retain() == false)
        #expect(driver.initializeCount == 1)
        platform.release()
        #expect(driver.terminateCount == 0)

        driver.initializationSucceeds = true
        #expect(platform.retain())
        #expect(driver.initializeCount == 2)
        platform.release()
        #expect(driver.terminateCount == 1)
    }
}

/// Records platform calls for GLFW reference-counting tests.
@MainActor
private final class RecordingGLFWPlatformDriver: GLFWPlatformDriver {
    /// Whether a simulated GLFW initialization succeeds.
    var initializationSucceeds = true

    /// The number of simulated GLFW initialization attempts.
    private(set) var initializeCount = 0

    /// The number of simulated GLFW termination calls.
    private(set) var terminateCount = 0

    /// Records an initialization attempt and returns its configured result.
    func initialize() -> Bool {
        initializeCount += 1
        return initializationSucceeds
    }

    /// Records a termination call.
    func terminate() {
        terminateCount += 1
    }
}
