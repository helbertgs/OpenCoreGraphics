import Foundation
import Testing

#if os(macOS) || os(Linux)
/// Checks the supervisor without launching graphics or blocking the standard suite.
struct WindowBaselineRunnerTests {
    /// A synthetic report used only to test the supervisor's parser.
    private let completeReport = """
    WINDOW_BASELINE idle_seconds=2 idle_cpu_seconds=0.1 idle_cpu_percent_one_core=5 idle_iterations=120
    WINDOW_BASELINE events_posted=1 events_received=1 event_latency_ms=[1.0]
    WINDOW_BASELINE frames=1 animation_frames=1 idle_draws=0 second_automatic_frames=0 second_after_manual_redraw=1 task_during_loop=true task_at_return=true close_ms=1
    WINDOW_BASELINE COMPLETE
    """

    /// Runs a controlled child through the real deadline supervisor.
    private func run(_ source: String, timeout: Double = 5) throws -> (Int32, String) {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["ruby", root.appending(path: "scripts/run-window-baseline.rb").path,
                             "--timeout", String(timeout), "--", "ruby", "-e", source]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Rejects a child that exceeds the hard deadline.
    @Test
    func timeoutStopsChild() throws {
        let (status, output) = try run("sleep 10", timeout: 0.2)
        #expect(status != 0)
        #expect(output.contains("TIMEOUT"))
    }

    /// Rejects a partial report even if the child exits successfully.
    @Test
    func incompleteReportFails() throws {
        let (status, output) = try run("puts 'WINDOW_BASELINE COMPLETE'")
        #expect(status != 0)
        #expect(output.contains("INCOMPLETE"))
    }

    /// Accepts a complete report only when the child also exits successfully.
    @Test
    func completeReportPasses() throws {
        let (status, output) = try run("puts \(String(reflecting: completeReport))")
        #expect(status == 0)
        #expect(output.contains("RUNNER: PASSED"))
    }

    /// Rejects an unsuccessful child even when it emits a completion marker.
    @Test
    func failingChildFails() throws {
        let (status, output) = try run("puts \(String(reflecting: completeReport)); exit 3")
        #expect(status != 0)
        #expect(output.contains("FAILED"))
    }
}
#endif
