import Foundation
import Testing

#if os(macOS) || os(Linux)
/// Validates the external timeout and report required by the cooperative window probe.
struct WindowCooperativeRunnerTests {
    /// A complete synthetic report for testing the supervisor independently of graphics.
    private let report = """
    WINDOW_COOPERATIVE host_running
    WINDOW_COOPERATIVE precancelled
    WINDOW_COOPERATIVE duplicate_rejected
    WINDOW_COOPERATIVE idle_seconds=2 idle_cpu_seconds=0.1 idle_cpu_percent_one_core=5
    WINDOW_COOPERATIVE events_posted=20 events_received=20 event_latency_ms=[1.0]
    WINDOW_COOPERATIVE frames_a=3 frames_b=3 idle_draws_a=0 idle_draws_b=0 task_during_loop=true close_ms=1 second_survived_close=true cancellation_kept_visible=true restart_closed=true
    WINDOW_COOPERATIVE COMPLETE
    """

    /// Runs a controlled child through the actual supervisor.
    private func run(_ source: String, timeout: Double = 5, options: [String] = []) throws -> (Int32, String) {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["ruby", root.appending(path: "scripts/run-window-cooperative.rb").path,
                             "--timeout", String(timeout)] + options + ["--", "ruby", "-e", source]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// A stalled child is stopped even when the main actor cannot progress.
    @Test
    func timeoutStopsChild() throws {
        let (status, output) = try run("sleep 10", timeout: 0.2)
        #expect(status != 0)
        #expect(output.contains("TIMEOUT"))
    }

    /// A completion marker without the required observations is rejected.
    @Test
    func incompleteReportFails() throws {
        let (status, output) = try run("puts 'WINDOW_COOPERATIVE COMPLETE'")
        #expect(status != 0)
        #expect(output.contains("INCOMPLETE"))
    }

    /// A complete report and successful process are both required.
    @Test
    func completeReportPasses() throws {
        let (status, output) = try run("puts \(String(reflecting: report))")
        #expect(status == 0)
        #expect(output.contains("RUNNER: PASSED"))
    }

    /// A successful-looking report cannot hide an unsuccessful exit.
    @Test
    func failingChildFails() throws {
        let (status, output) = try run("puts \(String(reflecting: report)); exit 3")
        #expect(status != 0)
        #expect(output.contains("FAILED"))
    }

    /// A missing event cannot be accepted as a completed graphical experiment.
    @Test
    func missingEventFails() throws {
        let incomplete = report.replacing("events_received=20", with: "events_received=19")
        let (status, _) = try run("puts \(String(reflecting: incomplete))")
        #expect(status != 0)
    }

    /// A report cannot pass without observing the supported host's active event loop.
    @Test
    func missingHostFails() throws {
        let incomplete = report.replacing("WINDOW_COOPERATIVE host_running\n", with: "")
        let (status, _) = try run("puts \(String(reflecting: incomplete))")
        #expect(status != 0)
    }

    /// An async-main process that exits zero before its summary is still incomplete.
    @Test
    func asyncMainEarlyExitFails() throws {
        let output = """
        WINDOW_ASYNC_MAIN before_first_window
        WINDOW_ASYNC_MAIN first_window_created
        WINDOW_ASYNC_MAIN second_window_created
        """
        let (status, result) = try run("puts \(String(reflecting: output))", options: ["--async-main"])
        #expect(status != 0)
        #expect(result.contains("INCOMPLETE"))
    }

    /// A complete async-main report is accepted only with successful exit.
    @Test
    func asyncMainReportPasses() throws {
        let output = """
        WINDOW_ASYNC_MAIN before_first_window
        WINDOW_ASYNC_MAIN first_window_created
        WINDOW_ASYNC_MAIN second_window_created
        WINDOW_ASYNC_MAIN COMPLETE frames_a=2 frames_b=3 cancelled_without_closing=true
        """
        let (status, result) = try run("puts \(String(reflecting: output))", options: ["--async-main"])
        #expect(status == 0)
        #expect(result.contains("RUNNER: PASSED"))
    }

    /// An initialization error must be observed before the failure-path summary.
    @Test
    func initializationFailureRequiresSummary() throws {
        let (status, _) = try run(
            "puts 'WINDOW_ASYNC_MAIN before_first_window'; puts 'WINDOW_ASYNC_MAIN initialization_error_observed'",
            options: ["--async-main", "--initialization-failure"]
        )
        #expect(status != 0)
    }

    /// Runs the real graphical probe in a supervised process when explicitly requested.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENCOREGRAPHICS_RUN_WINDOW_COOPERATIVE"] == "1"))
    func graphicalProbeCompletes() async throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["ruby", root.appending(path: "scripts/run-window-cooperative.rb").path,
                             "--timeout", "45", "--",
                             root.appending(path: ".build/debug/OpenCoreGraphicsWindowCooperative").path]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        await confirmation("Graphical probe and its main-actor task completed") { confirmed in
            if process.terminationStatus == 0 && output.contains("WINDOW_COOPERATIVE RUNNER: PASSED") {
                confirmed()
            } else {
                Issue.record("Graphical probe incomplete: \(output)")
            }
        }
    }
}
#endif
