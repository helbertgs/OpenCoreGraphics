import Foundation

/// Exposes an isolated event pump to tests without creating a public API.
@MainActor
struct WindowLoopTestHandle {
    /// Registers one test participant and waits for its completion.
    let participate: @MainActor (
        UUID,
        ObjectIdentifier,
        @escaping @MainActor () -> Void,
        @escaping @MainActor () throws -> Bool
    ) async throws -> Void

    /// Cancels one registered test participant.
    let cancel: @MainActor (UUID) -> Void
}
