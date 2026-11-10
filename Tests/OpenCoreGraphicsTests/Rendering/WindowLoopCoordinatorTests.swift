import Foundation
import Testing
@testable import OpenCoreGraphics

/// Exercises the actual event coordinator using a controlled clock and event source.
@MainActor
struct WindowLoopCoordinatorTests {
    /// Two participants are advanced fairly; cancellation removes only its owner.
    @Test(.timeLimit(.minutes(1)))
    func coordinatesWindowsAndCancellation() async throws {
        let (pauseEvents, pauseSignal) = AsyncStream<Void>.makeStream()
        var pauses = pauseEvents.makeAsyncIterator()
        let (shownEvents, shownSignal) = AsyncStream<Void>.makeStream()
        var shown = shownEvents.makeAsyncIterator()
        var resumePump: CheckedContinuation<Void, Never>?
        var polls = 0
        let coordinator = WindowLoopCoordinator.makeForTesting(
            { polls += 1 },
            {
                await withCheckedContinuation { continuation in
                    resumePump = continuation
                    pauseSignal.yield()
                }
            }
        )
        let a = NSObject()
        let b = NSObject()
        let idA = UUID()
        let idB = UUID()
        var aFrames = 0
        var bFrames = 0
        var bCloses = false
        let taskA = Task { @MainActor in
            try await coordinator.participate(idA, ObjectIdentifier(a), {}, {
                aFrames += 1
                return true
            })
        }
        defer { taskA.cancel(); pauseSignal.finish(); shownSignal.finish() }
        _ = await pauses.next()
        #expect(polls == 1)
        #expect(aFrames == 1)

        let taskB = Task { @MainActor in
            try await coordinator.participate(idB, ObjectIdentifier(b), { shownSignal.yield() }, {
                bFrames += 1
                return !bCloses
            })
        }
        defer { taskB.cancel() }
        _ = await shown.next()

        do {
            try await coordinator.participate(UUID(), ObjectIdentifier(a), {}, { true })
            Issue.record("A duplicate window was accepted")
        } catch {
            #expect(!(error is CancellationError))
        }
        resumePump?.resume()
        _ = await pauses.next()
        #expect(polls == 2)
        #expect(aFrames == 2)
        #expect(bFrames == 1)

        coordinator.cancel(idA)
        do {
            try await taskA.value
            Issue.record("Cancellation did not throw")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
        coordinator.cancel(idA)
        bCloses = true
        resumePump?.resume()
        try await taskB.value
        #expect(aFrames == 2)
        #expect(bFrames == 2)
        #expect(polls == 3)
    }

    /// A participant failure does not prevent another window from progressing.
    @Test(.timeLimit(.minutes(1)))
    func isolatesParticipantFailure() async throws {
        let (pauseEvents, pauseSignal) = AsyncStream<Void>.makeStream()
        var pauses = pauseEvents.makeAsyncIterator()
        let (shownEvents, shownSignal) = AsyncStream<Void>.makeStream()
        var shown = shownEvents.makeAsyncIterator()
        var resumePump: CheckedContinuation<Void, Never>?
        let coordinator = WindowLoopCoordinator.makeForTesting(
            {},
            {
                await withCheckedContinuation { continuation in
                    resumePump = continuation
                    pauseSignal.yield()
                }
            }
        )
        let a = NSObject()
        let b = NSObject()
        var failA = false
        var bFrames = 0
        let taskA = Task { @MainActor in
            try await coordinator.participate(UUID(), ObjectIdentifier(a), {}, {
                if failA { throw TestFailure.expected }
                return true
            })
        }
        _ = await pauses.next()
        let taskB = Task { @MainActor in
            try await coordinator.participate(UUID(), ObjectIdentifier(b), { shownSignal.yield() }, {
                bFrames += 1
                return false
            })
        }
        _ = await shown.next()
        failA = true
        resumePump?.resume()
        do {
            try await taskA.value
            Issue.record("Expected a participant failure")
        } catch TestFailure.expected {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        try await taskB.value
        #expect(bFrames == 1)
        pauseSignal.finish()
        shownSignal.finish()
    }
}

/// An injected failure in one window's frame.
private enum TestFailure: Error {
    /// The expected test failure.
    case expected
}
