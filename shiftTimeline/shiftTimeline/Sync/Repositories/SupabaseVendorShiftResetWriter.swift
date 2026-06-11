import Foundation
import Supabase

/// Pushes the planner's post-shift acknowledgment reset to Supabase.
///
/// When the planner commits a shift, every affected vendor's acknowledgment is
/// reset: `has_acknowledged_latest_shift = false` and `pending_shift_delta` is
/// stamped with the new drift. The planner owns the event, so the owner RLS policy
/// (`event_vendors_owner_all`) permits writing these columns — this is a targeted
/// update, not a full-row upsert.
protocol VendorShiftResetWriting: Sendable {
    func resetAcknowledgment(eventVendorID: UUID, pendingShiftDelta: Double) async throws
}

/// Supabase-backed `VendorShiftResetWriting`. Stateless — holds only the client.
struct SupabaseVendorShiftResetWriter: VendorShiftResetWriting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func resetAcknowledgment(eventVendorID: UUID, pendingShiftDelta: Double) async throws {
        try await client
            .from("event_vendors")
            .update(AckResetPatch(hasAcknowledgedLatestShift: false, pendingShiftDelta: pendingShiftDelta))
            .eq("id", value: eventVendorID.uuidString)
            .execute()
    }

    /// The two columns a shift reset touches; named via CodingKeys so the JSON
    /// matches the Postgres snake_case columns.
    private struct AckResetPatch: Encodable, Sendable {
        let hasAcknowledgedLatestShift: Bool
        let pendingShiftDelta: Double

        enum CodingKeys: String, CodingKey {
            case hasAcknowledgedLatestShift = "has_acknowledged_latest_shift"
            case pendingShiftDelta = "pending_shift_delta"
        }
    }
}
