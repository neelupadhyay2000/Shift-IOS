import Foundation
import Supabase

/// Writes a vendor's shift acknowledgment to Supabase.
///
/// A vendor may write **only** `has_acknowledged_latest_shift` on their own
/// `event_vendors` row — enforced server-side by the column-restricted RLS policy
/// `event_vendors_vendor_update_ack` (`using profile_id = auth.uid()` +
/// `event_vendor_ack_only_changed` WITH CHECK). This is therefore a targeted
/// single-column `UPDATE`, never a full-row upsert (which RLS would reject), so it
/// patches just that column and leaves everything else for the WITH CHECK to verify
/// unchanged.
protocol VendorAckWriting: Sendable {
    /// Sets `has_acknowledged_latest_shift` on the given `event_vendors` row.
    func setAcknowledged(eventVendorID: UUID, to value: Bool) async throws
}

/// Supabase-backed `VendorAckWriting`. Stateless — holds only the shared client.
struct SupabaseVendorAckWriter: VendorAckWriting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func setAcknowledged(eventVendorID: UUID, to value: Bool) async throws {
        try await client
            .from("event_vendors")
            .update(["has_acknowledged_latest_shift": value])
            .eq("id", value: eventVendorID.uuidString)
            .execute()
    }
}
