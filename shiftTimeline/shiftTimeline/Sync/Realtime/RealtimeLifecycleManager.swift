import Foundation

/// Owns the realtime channel's lifecycle so the app holds a Supabase connection
/// only when it's useful: a channel is open **iff** the app is foregrounded and
/// the user has an event open.
///
/// Drive it from the UI layer:
/// - `setActiveEvent(_:)` when an event detail view appears (`id`) / disappears (`nil`);
/// - `didEnterForeground()` / `didEnterBackground()` on `scenePhase` changes.
///
/// Each (re)subscribe opens a fresh stream via the injected factory and consumes
/// it on a `Task`; tearing down cancels that `Task`, which cascades to
/// `RealtimeSyncService`'s `unsubscribe()` (the stream's `onTermination`).
@MainActor
final class RealtimeLifecycleManager {
    private let openStream: @MainActor (UUID) -> AsyncStream<RealtimeChange>
    private let consume: @MainActor (AsyncStream<RealtimeChange>) async -> Void

    private var activeEventID: UUID?
    private var isForeground: Bool

    /// The event whose channel is currently open, or `nil` when none.
    private(set) var streamingEventID: UUID?

    // nonisolated(unsafe) so the nonisolated `deinit` can cancel it; every other
    // access is on the main actor (matches `SubscriptionManager`'s pattern).
    private nonisolated(unsafe) var streamTask: Task<Void, Never>?

    /// Whether a channel is currently open.
    var isStreaming: Bool { streamTask != nil }

    init(
        openStream: @escaping @MainActor (UUID) -> AsyncStream<RealtimeChange>,
        consume: @escaping @MainActor (AsyncStream<RealtimeChange>) async -> Void,
        isForeground: Bool = true
    ) {
        self.openStream = openStream
        self.consume = consume
        self.isForeground = isForeground
    }

    /// Production wiring: stream from `RealtimeSyncService`, apply via `RealtimeChangeApplier`.
    convenience init(
        service: RealtimeSyncService,
        applier: RealtimeChangeApplier,
        isForeground: Bool = true
    ) {
        self.init(
            openStream: { service.changes(forEvent: $0) },
            consume: { await applier.apply($0) },
            isForeground: isForeground
        )
    }

    /// The event the user is viewing, or `nil` when none. Subscribes to it while
    /// foregrounded and tears down any previous event's channel.
    func setActiveEvent(_ eventID: UUID?) {
        guard eventID != activeEventID else { return }
        activeEventID = eventID
        reconcile()
    }

    /// App returned to the foreground — resubscribe to the active event.
    func didEnterForeground() {
        guard !isForeground else { return }
        isForeground = true
        reconcile()
    }

    /// App went to the background — tear the channel down to free the connection.
    func didEnterBackground() {
        guard isForeground else { return }
        isForeground = false
        reconcile()
    }

    /// Opens a channel exactly when foregrounded with an active event, closing it
    /// otherwise; a no-op when already in the desired state.
    private func reconcile() {
        guard isForeground, let eventID = activeEventID else {
            stopStream()
            return
        }
        guard streamingEventID != eventID else { return }
        startStream(for: eventID)
    }

    private func startStream(for eventID: UUID) {
        stopStream()
        streamingEventID = eventID
        let stream = openStream(eventID)
        streamTask = Task { [consume] in
            await consume(stream)
        }
    }

    private func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        streamingEventID = nil
    }

    deinit {
        streamTask?.cancel()
    }
}
