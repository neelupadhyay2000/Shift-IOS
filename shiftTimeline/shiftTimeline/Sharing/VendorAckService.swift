import Foundation
import Models

/// Acknowledges the latest shift for a vendor (SHIFT-632).
///
/// Split into an optimistic local update and the remote write so the UI can
/// animate the banner dismissal on the synchronous local step, then push to
/// Supabase. Only `has_acknowledged_latest_shift` is sent — the single column the
/// vendor's RLS policy permits; `pendingShiftDelta` is cleared locally for an
/// immediate banner dismissal but is never written (the vendor can't, and it's
/// reset server-side by the planner on the next shift, SHIFT-634).
@MainActor
struct VendorAckService {

    private let writer: any VendorAckWriting

    init(writer: any VendorAckWriting) {
        self.writer = writer
    }

    /// Optimistic local acknowledgment — synchronous so the caller can wrap it in
    /// `withAnimation` for the banner dismissal.
    func applyLocalAck(_ vendor: VendorModel) {
        vendor.hasAcknowledgedLatestShift = true
        vendor.pendingShiftDelta = nil
    }

    /// Writes only `has_acknowledged_latest_shift` for this vendor's row.
    func pushAck(_ vendor: VendorModel) async throws {
        try await writer.setAcknowledged(eventVendorID: vendor.id, to: true)
    }

    /// Convenience: optimistic local update followed by the remote write.
    func acknowledge(_ vendor: VendorModel) async throws {
        applyLocalAck(vendor)
        try await pushAck(vendor)
    }
}
