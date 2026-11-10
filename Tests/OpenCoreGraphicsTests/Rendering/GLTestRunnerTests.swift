import Foundation
import Testing

#if os(macOS) || os(Linux)
/// Verifies that the GL test runner detects incomplete or unsuccessful test processes.
struct GLTestRunnerTests {
    /// Represents a process outcome and the combined output returned by the runner.
    private struct Result {
        /// The runner's exit status.
        let status: Int32

        /// The runner's standard output and standard error.
        let output: String
    }

    /// Runs the runner with a controlled Ruby child process that does not require OpenGL.
    /// - Parameters:
    ///   - source: Ruby source to execute in the child process.
    ///   - timeout: The runner deadline in seconds.
    /// - Returns: The runner's exit status and combined output.
    private func run(_ source: String, timeout: Double = 5) throws -> Result {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "ruby", root.appending(path: "scripts/run-gl-tests.rb").path,
            "--timeout", String(timeout), "--", "ruby", "-e", source
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// A valid Swift Testing report for the two opt-in GL tests.
    private var successOutput: String {
        """
        ✔ Test comparesSharedScenesAcrossBackends() passed after 0.001 seconds.
        ✔ Test comparesGlyphRenderingAcrossBackends() passed after 0.001 seconds.
        ✔ Test run with 2 tests in 2 suites passed after 0.001 seconds.
        """
    }

    /// Accepts only a successful process with both test results and a final summary.
    @Test
    private func successfulReportPasses() throws {
        let result = try run("puts \(String(reflecting: successOutput))")
        #expect(result.status == 0)
        #expect(result.output.contains("GL runner: PASSED"))
    }

    /// Rejects explicit assertion failures even if the child exits successfully.
    @Test
    private func failureWithZeroExitIsRejected() throws {
        let report = """
        ✘ Test comparesSharedScenesAcrossBackends() failed after 0.001 seconds.
        ✔ Test comparesGlyphRenderingAcrossBackends() passed after 0.001 seconds.
        ✘ Test run with 2 tests in 2 suites failed after 0.001 seconds.
        """
        let result = try run("puts \(String(reflecting: report))")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: FAILED"))
    }

    /// Rejects a successful exit when the final test report is missing.
    @Test
    private func incompleteReportIsRejected() throws {
        let result = try run("puts 'Test run started.'")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: INCOMPLETE"))
    }

    /// Rejects test runs that exceed the configured deadline.
    @Test
    private func timeoutIsRejected() throws {
        let result = try run("sleep 10", timeout: 0.2)
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: TIMEOUT"))
    }

    /// Distinguishes an unavailable graphics environment from an ordinary test failure.
    @Test
    private func unavailableGraphicsIsReportedSeparately() throws {
        let report = """
        GL_RUNNER_GRAPHICS_UNAVAILABLE: glfwInitFailed
        ✘ Test comparesSharedScenesAcrossBackends() failed after 0.001 seconds.
        ✔ Test comparesGlyphRenderingAcrossBackends() passed after 0.001 seconds.
        ✘ Test run with 2 tests in 2 suites failed after 0.001 seconds.
        """
        let result = try run("puts \(String(reflecting: report)); exit 1")
        #expect(result.status == 2)
        #expect(result.output.contains("GL runner: GRAPHICS_UNAVAILABLE"))
    }

    /// Rejects a skipped test even if the test process claims success.
    @Test
    private func skippedTestIsRejected() throws {
        let report = """
        ➜ Test comparesSharedScenesAcrossBackends() skipped.
        \(successOutput)
        """
        let result = try run("puts \(String(reflecting: report))")
        #expect(result.status == 1)
    }

    /// Rejects termination by a signal rather than treating it as success.
    @Test
    private func interruptedProcessIsRejected() throws {
        let result = try run("Process.kill('TERM', Process.pid); sleep 1")
        #expect(result.status == 1)
        #expect(result.output.contains("terminated by signal"))
    }

    /// Does not hide an unrelated assertion failure when graphics are unavailable for another test.
    @Test
    private func unrelatedFailureIsNotClassifiedAsUnavailable() throws {
        let report = """
        GL_RUNNER_GRAPHICS_UNAVAILABLE: glfwInitFailed
        ✘ Test comparesSharedScenesAcrossBackends() failed after 0.001 seconds.
        ✘ Test comparesGlyphRenderingAcrossBackends() failed after 0.001 seconds.
        ✘ Test run with 2 tests in 2 suites failed after 0.001 seconds.
        """
        let result = try run("puts \(String(reflecting: report)); exit 1")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: FAILED"))
    }
}
#endif
