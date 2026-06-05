import Foundation
import Supabase

/// Periodically hard-deletes old tombstones so the soft-deleted rows can't grow
/// unbounded (SHIFT-618).
///
/// Soft-delete keeps a deleted row around (with `deleted_at` set) long enough for
/// every device — including one that was offline — to learn of the deletion via
/// the delta. Once a tombstone is older than `retention` (well beyond any
/// realistic offline window), it's safe to remove for good. The delete is
/// RLS-scoped, so a device only reaps tombstones it owns; running it on several
/// owner devices is idempotent.
///
/// Drive it periodically (launch/foreground) — the cutover wiring. A server-side
/// scheduled job (`pg_cron`) is an equivalent alternative; this is the client
/// path. Nonisolated so the deletes run off the main actor.
nonisolated struct TombstonePurger {
    private let client: SupabaseClient
    private let retention: TimeInterval

    /// Every table that carries a `deleted_at` tombstone column.
    private static let tables = [
        "events", "tracks", "blocks", "event_vendors",
        "shift_records", "block_vendors", "block_dependencies",
    ]

    /// - Parameter retention: how long a tombstone is kept before it's reaped.
    ///   Default 30 days — must exceed the longest expected offline span so no
    ///   device misses a deletion.
    init(client: SupabaseClient, retention: TimeInterval = 30 * 24 * 60 * 60) {
        self.client = client
        self.retention = max(0, retention)
    }

    /// Removes every tombstone older than the retention cutoff. Live rows
    /// (`deleted_at IS NULL`) never match `deleted_at < cutoff`, so they're safe.
    func purge(now: Date = Date()) async throws {
        let cutoff = SupabaseTimestamp.string(from: Self.cutoffDate(now: now, retention: retention))
        for table in Self.tables {
            try await client.from(table)
                .delete()
                .lt("deleted_at", value: cutoff)
                .execute()
        }
    }

    /// The instant before which tombstones are reaped: `now - retention`.
    static func cutoffDate(now: Date, retention: TimeInterval) -> Date {
        now.addingTimeInterval(-retention)
    }
}
