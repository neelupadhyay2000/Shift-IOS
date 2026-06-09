import Foundation

/// Models the Supabase Realtime concurrent-connection budget so the cutover can
/// be reasoned about against the plan tier (SHIFT-663).
///
/// **Why one connection per device is the unit of accounting.** A device opens
/// **at most one** Realtime connection: `RealtimeLifecycleManager` keeps a single
/// channel open, and only while the app is foregrounded with an event open; that
/// one channel multiplexes all seven of the event's table bindings
/// (`RealtimeSyncService.subscribedTables`). So the fleet-wide concurrent-connection
/// count is bounded by the number of devices **simultaneously** foreground-on-an-event
/// — not by events × tables, and not by total installs. The vast majority of
/// users (signed-out, backgrounded, or just browsing the roster) hold zero
/// connections.
///
/// **Tier ceilings.** Supabase's documented peak concurrent Realtime connections
/// are ~200 (Free) and ~500 (Pro), raisable on paid plans. Treat these as inputs
/// to verify against the live plan — `usableConnections` reserves headroom under
/// the ceiling so a spike never saturates the tier (the rollout doc's "<70% of
/// tier ceiling at projected peak" budget).
struct RealtimeConnectionBudget: Sendable, Equatable {
    /// The plan tier's max concurrent Realtime connections.
    let tierCeiling: Int
    /// Connections a single foreground-on-an-event device holds open.
    /// `RealtimeLifecycleManager` caps this at 1.
    let connectionsPerActiveDevice: Int
    /// Fraction of the ceiling held in reserve (0–1). `0.3` ⇒ plan to use ≤70%.
    let headroomFraction: Double

    /// The ceiling after reserving headroom — the number to actually plan against.
    var usableConnections: Int {
        let clamped = min(max(headroomFraction, 0), 1)
        return Int((Double(tierCeiling) * (1 - clamped)).rounded(.down))
    }

    /// Max simultaneously-active devices that fit under the usable ceiling.
    var maxConcurrentDevices: Int {
        guard connectionsPerActiveDevice > 0 else { return 0 }
        return usableConnections / connectionsPerActiveDevice
    }

    /// Whether the expected peak of simultaneously-active devices fits the budget.
    func isWithinBudget(expectedConcurrentDevices devices: Int) -> Bool {
        devices * connectionsPerActiveDevice <= usableConnections
    }

    /// Free tier: ~200 concurrent connections, 30% reserved ⇒ ~140 active devices.
    static let free = RealtimeConnectionBudget(
        tierCeiling: 200, connectionsPerActiveDevice: 1, headroomFraction: 0.3
    )

    /// Pro tier: ~500 concurrent connections, 30% reserved ⇒ ~350 active devices.
    static let pro = RealtimeConnectionBudget(
        tierCeiling: 500, connectionsPerActiveDevice: 1, headroomFraction: 0.3
    )
}
