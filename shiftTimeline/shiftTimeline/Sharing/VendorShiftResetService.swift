import Foundation
import Models

/// One vendor's post-shift reset — a Sendable snapshot so the remote push can run
/// detached without capturing SwiftData models.
struct VendorAckReset: Sendable, Equatable {
    let eventVendorID: UUID
    let pendingShiftDelta: Double
}

/// Propagates the planner's post-shift acknowledgment reset to Supabase (SHIFT-634).
///
/// `VendorShiftNotifier.applyThresholdNotifications` already resets the local
/// vendor models (`hasAcknowledgedLatestShift = false` + `pendingShiftDelta`). This
/// service snapshots that result and pushes it so each affected vendor's row on
/// Supabase reflects the new shift — the vendor's device then shows the
/// acknowledgment banner again (via realtime) and the planner's ack grid shows them
/// pending. The planner owns the rows, so the write is RLS-permitted.
struct VendorShiftResetService: Sendable {

    private let writer: any VendorShiftResetWriting

    init(writer: any VendorShiftResetWriting) {
        self.writer = writer
    }

    /// Production instance backed by the shared Supabase client.
    static var live: VendorShiftResetService {
        VendorShiftResetService(writer: SupabaseVendorShiftResetWriter(client: SupabaseClientProvider.shared.client))
    }

    /// Snapshots each vendor's reset state. Call right after
    /// `VendorShiftNotifier.applyThresholdNotifications`, in the same context, to
    /// produce a Sendable payload safe to hand to a detached push `Task`.
    nonisolated static func resets(for event: EventModel) -> [VendorAckReset] {
        (event.vendors ?? []).compactMap { vendor in
            vendor.pendingShiftDelta.map {
                VendorAckReset(eventVendorID: vendor.id, pendingShiftDelta: $0)
            }
        }
    }

    /// Pushes `has_acknowledged_latest_shift = false` + the new pending delta for
    /// each vendor. Best-effort per row — a failed push just means that vendor
    /// learns of the reset on the next sync.
    func pushReset(_ resets: [VendorAckReset]) async {
        for reset in resets {
            try? await writer.resetAcknowledgment(
                eventVendorID: reset.eventVendorID,
                pendingShiftDelta: reset.pendingShiftDelta
            )
        }
    }
}
