import Foundation
import SwiftData

/// A pending write that has not yet been flushed to Supabase.
///
/// Every mutation through the Repository layer appends one entry here.
/// The SyncEngine (E-SB5) reads entries FIFO, posts them to Supabase,
/// and deletes them on success. On conflict or network failure the entry
/// is re-queued with an incremented `attempts` count and exponential backoff.
///
/// This model is local-only — it is never mirrored to Supabase.
@Model
public final class OutboxEntry {
    public var id: UUID = UUID()
    /// Monotonic, gap-free, strictly-increasing position assigned at enqueue time
    /// (per device). This is the authoritative FIFO key: the SyncEngine flushes
    /// entries in ascending `sequence` order so causally-dependent writes (a parent
    /// row enqueued before its child) always flush parent-first. `createdAt` is a
    /// human-readable timestamp only — it has no deterministic tiebreaker on ties,
    /// so it must not be relied on for ordering. Assignment lives in the repository
    /// enqueue path; the default `0` is a placeholder for unassigned rows.
    public var sequence: Int = 0
    /// The Supabase table this entry targets: "events", "tracks", "blocks",
    /// "event_vendors", "block_vendors", "shift_records".
    public var tableName: String = ""
    /// The `id` of the affected row in that table.
    public var rowID: UUID = UUID()
    /// One of "insert", "update", "delete".
    public var operation: String = ""
    /// JSON-encoded snapshot or diff. `nil` for delete operations.
    public var payload: Data?
    /// Wall-clock time of the local write. Diagnostic/auditing only — see `sequence`
    /// for the FIFO ordering key.
    public var createdAt: Date = Date()
    /// Number of failed flush attempts; drives exponential backoff in the SyncEngine.
    public var attempts: Int = 0

    public init(
        id: UUID = UUID(),
        sequence: Int = 0,
        tableName: String,
        rowID: UUID,
        operation: String,
        payload: Data? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.tableName = tableName
        self.rowID = rowID
        self.operation = operation
        self.payload = payload
    }
}
