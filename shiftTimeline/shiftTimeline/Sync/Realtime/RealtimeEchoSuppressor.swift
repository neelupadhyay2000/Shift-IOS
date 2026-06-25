import Foundation

/// Suppresses the realtime echoes of this device's own writes.
///
/// Every write goes out optimistically to the local store and to Supabase, then
/// comes back over Realtime as an INSERT/UPDATE — an *echo*. Re-applying that
/// echo is at best wasted work that flickers `@Query` views, and at worst
/// clobbers a newer local edit the device made before the echo arrived.
///
/// There's no `origin` column and the models don't carry a server `updated_at`,
/// so we suppress by recency: the outbox flush records every row it writes
/// (it already knows the `table`+`id`), and the
/// realtime applier skips any change for a row this device wrote within the
/// echo `window`. Once the window lapses, later changes (including a genuine
/// edit from another device) apply normally.
///
/// Precise per-version matching (origin tag / captured `updated_at`) is a future
/// refinement; this reliably kills the common single-edit echo and protects an
/// in-progress local edit, which is what the acceptance needs.
@MainActor
final class RealtimeEchoSuppressor {
    private var recentWrites: [String: Date] = [:]
    private let window: TimeInterval
    private let clock: () -> Date

    init(window: TimeInterval = 10, clock: @escaping () -> Date = { Date() }) {
        self.window = window
        self.clock = clock
    }

    /// Records that this device just wrote `id` in `table`, so the matching
    /// realtime echo can be recognized and skipped.
    func recordLocalWrite(table: String, id: UUID) {
        recentWrites[key(table, id)] = clock()
        prune()
    }

    /// Whether a realtime change for `id` in `table` should be skipped because
    /// this device wrote that row within the echo window.
    func shouldSuppress(table: String, id: UUID) -> Bool {
        guard let writtenAt = recentWrites[key(table, id)] else { return false }
        return clock().timeIntervalSince(writtenAt) <= window
    }

    private func key(_ table: String, _ id: UUID) -> String {
        "\(table):\(id.uuidString)"
    }

    /// Drops entries older than the window so the map can't grow unbounded.
    private func prune() {
        let cutoff = clock().addingTimeInterval(-window)
        recentWrites = recentWrites.filter { $0.value >= cutoff }
    }
}
