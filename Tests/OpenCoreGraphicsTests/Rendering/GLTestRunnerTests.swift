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

    /// A valid report for the opt-in GL tests and three synthetic metric tests.
    private var successOutput: String {
        let reports = ["above", "below", "rotation", "horizontal", "vertical", "order", "spacing"]
            .flatMap { scene in
                ["mean", "local"].map { metric in
                    "GL_COMPARISON: glyph_\(scene)_\(metric) PASSED difference=0.0 tolerance=0.015"
                }
            }.joined(separator: "\n")
        return """
        \(reports)
        GL_COMPARISON: mutable_before PASSED difference=0.0 tolerance=0.007
        GL_COMPARISON: mutable_after PASSED difference=0.0 tolerance=0.007
        GL_COMPARISON: mutable_queued PASSED difference=0.0 tolerance=0.007
        GL_TEXTURE_CACHE_METRICS: frames=6 uploads=5 updates=1 uploadedBytes=20 retainedBytes=8,8,16,16,16,16 budgetBytes=16 evictions=2 externallyRetainedBytes=8
        GL_TEXTURE_CACHE_REAL: updates=1 evictions=1 retainedBytes=8 budgetBytes=8 updatedPixel=[0, 0, 255, 255] evictedPixel=[0, 255, 0, 255] lifetime=verified
        ✔ Test comparesSharedScenesAcrossBackends() passed after 0.001 seconds.
        ✔ Test comparesGlyphRenderingAcrossBackends() passed after 0.001 seconds.
        ✔ Test preservesContentAndBudgetAcrossFrameSequence() passed after 0.001 seconds.
        ✔ Test updatesAndEvictsRealTexturesWithoutChangingRenderedPixels() passed after 0.001 seconds.
        ✔ Test localFailureCannotHideInMean() passed after 0.001 seconds.
        ✔ Test identicalWrongBackendsFailReference() passed after 0.001 seconds.
        ✔ Test invalidBuffersAreRejected() passed after 0.001 seconds.
        ✔ Test run with 28 tests in 5 suites passed after 0.001 seconds.
        """
    }

    /// Rejects a successful summary when a mutable-image comparison was not reported.
    @Test
    private func missingMutableImageReportIsRejected() throws {
        let incomplete = successOutput.replacing(
            "GL_COMPARISON: mutable_after PASSED difference=0.0 tolerance=0.007\n", with: ""
        )
        let result = try run("puts \(String(reflecting: incomplete))")
        #expect(result.status == 1)
        #expect(result.output.contains("mutable-image reports"))
    }

    /// Rejects a successful run when deterministic or real texture-cache evidence is absent.
    @Test
    private func missingTextureCacheEvidenceIsRejected() throws {
        let evidence = [
            "GL_TEXTURE_CACHE_METRICS: frames=6 uploads=5 updates=1 uploadedBytes=20 retainedBytes=8,8,16,16,16,16 budgetBytes=16 evictions=2 externallyRetainedBytes=8\n",
            "GL_TEXTURE_CACHE_REAL: updates=1 evictions=1 retainedBytes=8 budgetBytes=8 updatedPixel=[0, 0, 255, 255] evictedPixel=[0, 255, 0, 255] lifetime=verified\n"
        ]
        for report in evidence {
            let incomplete = successOutput.replacing(report, with: "")
            let result = try run("puts \(String(reflecting: incomplete))")
            #expect(result.status == 1)
            #expect(result.output.contains("texture-cache evidence"))
        }
    }

    /// Rejects real OpenGL pixel evidence that does not match the asserted update color.
    @Test
    private func invalidRealTextureCachePixelsAreRejected() throws {
        let invalid = successOutput.replacing(
            "updatedPixel=[0, 0, 255, 255]",
            with: "updatedPixel=[255, 0, 0, 255]"
        )
        let result = try run("puts \(String(reflecting: invalid))")
        #expect(result.status == 1)
        #expect(result.output.contains("texture-cache evidence"))
    }

    /// Rejects inconsistent, duplicated, or overly permissive mutable-image reports.
    @Test
    private func invalidMutableImageReportsAreRejected() throws {
        let valid = "GL_COMPARISON: mutable_before PASSED difference=0.0 tolerance=0.007"
        let invalid = [
            "GL_COMPARISON: mutable_before PASSED difference=1.0 tolerance=0.007",
            "GL_COMPARISON: mutable_before PASSED difference=0.0 tolerance=1.0",
            "\(valid)\nGL_COMPARISON: mutable_before FAILED difference=1.0 tolerance=0.007"
        ]
        for report in invalid {
            let result = try run("puts \(String(reflecting: successOutput.replacing(valid, with: report)))")
            #expect(result.status == 1)
            #expect(result.output.contains("GL runner: FAILED"))
        }
    }

    /// Rejects an otherwise successful run that omits localized glyph evidence.
    @Test
    private func missingGlyphReportIsRejected() throws {
        let incomplete = successOutput.replacing(
            "GL_COMPARISON: glyph_above_local PASSED difference=0.0 tolerance=0.015\n", with: ""
        )
        let result = try run("puts \(String(reflecting: incomplete))")
        #expect(result.status == 1)
        #expect(result.output.contains("missing glyph reports"))
    }

    /// Rejects conflicting local outcomes even if a passing report and summary are present.
    @Test
    private func conflictingGlyphReportIsRejected() throws {
        let report = """
        \(successOutput)
        GL_COMPARISON: glyph_above_local FAILED difference=1.0 tolerance=0.015
        """
        let result = try run("puts \(String(reflecting: report))")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: FAILED"))
    }

    /// Rejects a passing label when the numeric localized difference exceeds its tolerance.
    @Test
    private func inconsistentGlyphReportIsRejected() throws {
        let report = successOutput.replacing(
            "glyph_above_local PASSED difference=0.0 tolerance=0.015",
            with: "glyph_above_local PASSED difference=1.0 tolerance=0.015"
        )
        let result = try run("puts \(String(reflecting: report))")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: FAILED"))
    }

    /// Rejects an artificially permissive local threshold even when the reported value passes.
    @Test
    private func excessiveGlyphToleranceIsRejected() throws {
        let report = successOutput.replacing(
            "glyph_above_local PASSED difference=0.0 tolerance=0.015",
            with: "glyph_above_local PASSED difference=0.0 tolerance=1.0"
        )
        let result = try run("puts \(String(reflecting: report))")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: FAILED"))
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
        ✘ Test comparesSharedScenesAcrossBackends() failed after 0.001 seconds with 1 issue.
        ✔ Test comparesGlyphRenderingAcrossBackends() passed after 0.001 seconds.
        ✔ Test updatesAndEvictsRealTexturesWithoutChangingRenderedPixels() passed after 0.001 seconds.
        ✘ Test run with 28 tests in 5 suites failed after 0.001 seconds with 1 issue.
        """
        let result = try run("puts \(String(reflecting: report))")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: FAILED"))
    }

    /// Recognizes the Swift Testing summary suffix used when assertions fail.
    @Test
    private func failureWithIssueCountIsComplete() throws {
        let report = """
        ✘ Test comparesSharedScenesAcrossBackends() failed after 0.001 seconds with 5 issues.
        ✔ Test comparesGlyphRenderingAcrossBackends() passed after 0.001 seconds.
        ✔ Test updatesAndEvictsRealTexturesWithoutChangingRenderedPixels() passed after 0.001 seconds.
        ✘ Test run with 28 tests in 5 suites failed after 0.001 seconds with 5 issues.
        """
        let result = try run("puts \(String(reflecting: report)); exit 1")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: FAILED"))
        #expect(result.output.contains("GL runner: INCOMPLETE") == false)
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
        GL_RUNNER_GRAPHICS_UNAVAILABLE: glfwInitFailed
        ✘ Test comparesSharedScenesAcrossBackends() failed after 0.001 seconds with 1 issue.
        ✔ Test comparesGlyphRenderingAcrossBackends() passed after 0.001 seconds.
        ✘ Test updatesAndEvictsRealTexturesWithoutChangingRenderedPixels() failed after 0.001 seconds with 1 issue.
        ✘ Test run with 28 tests in 5 suites failed after 0.001 seconds with 2 issues.
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
        #expect(result.output.contains("GL runner: SKIPPED"))
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
        ✘ Test updatesAndEvictsRealTexturesWithoutChangingRenderedPixels() failed after 0.001 seconds.
        ✘ Test run with 28 tests in 5 suites failed after 0.001 seconds.
        """
        let result = try run("puts \(String(reflecting: report)); exit 1")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: FAILED"))
    }

    /// Does not mistake a synthetic metric failure for a graphics availability failure.
    @Test
    private func syntheticFailureIsNotClassifiedAsUnavailable() throws {
        let report = """
        GL_RUNNER_GRAPHICS_UNAVAILABLE: glfwInitFailed
        ✘ Test comparesSharedScenesAcrossBackends() failed after 0.001 seconds.
        ✘ Test localFailureCannotHideInMean() failed after 0.001 seconds.
        ✘ Test run with 28 tests in 5 suites failed after 0.001 seconds.
        """
        let result = try run("puts \(String(reflecting: report)); exit 1")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: FAILED"))
    }

    /// Rejects a missing synthetic test even when the remaining results claim success.
    @Test
    private func missingMetricTestIsRejected() throws {
        let report = successOutput.replacing(
            "✔ Test invalidBuffersAreRejected() passed after 0.001 seconds.\n", with: ""
        )
        let result = try run("puts \(String(reflecting: report))")
        #expect(result.status == 1)
        #expect(result.output.contains("GL runner: FAILED"))
    }
}
#endif
