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
/// E-SB5 owns the read/flush/delete lifecycle; this file is the placeholder.
@Model
public final class OutboxEntry {
    public var id: UUID = UUID()
    /// The Supabase table this entry targets: "events", "tracks", "blocks",
    /// "event_vendors", "block_vendors", "shift_records".
    public var tableName: String = ""
    /// The `id` of the affected row in that table.
    public var rowID: UUID = UUID()
    /// One of "insert", "update", "delete". E-SB5 may promote this to a typed enum.
    public var operation: String = ""
    /// JSON-encoded snapshot or diff. `nil` for delete operations.
    public var payload: Data?
    /// Wall-clock time of the local write; used for FIFO ordering.
    public var createdAt: Date = Date()
    /// Number of failed flush attempts; drives exponential backoff in the SyncEngine.
    public var attempts: Int = 0

    public init(
        id: UUID = UUID(),
        tableName: String,
        rowID: UUID,
        operation: String,
        payload: Data? = nil
    ) {
        self.id = id
        self.tableName = tableName
        self.rowID = rowID
        self.operation = operation
        self.payload = payload
    }
}
