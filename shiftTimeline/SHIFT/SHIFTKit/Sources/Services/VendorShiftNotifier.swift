import Foundation
import Models
import os

/// After the planner commits a shift, this helper resets all vendor
/// acknowledgment flags and stamps `pendingShiftDelta` on every vendor
/// attached to the event.
///
/// `pendingShiftDelta` serves two purposes:
///   1. **In-app acknowledgment tracking** — the vendor-facing
///      `ShiftAcknowledgmentBanner` and the planner-facing `VendorAckGrid`
///      both read it to decide whether a vendor has an unacknowledged shift.
///      It is set on ALL vendors (even those below threshold or unassigned)
///      so the planner's grid shows every vendor as pending after a shift.
///   2. **Push notification trigger** — `VendorShiftLocalNotifier` reads it
///      on the vendor's device after CloudKit sync and posts a visible local
///      notification only when `abs(pendingShiftDelta) >= notificationThreshold`.
///
/// The field is cleared when the vendor taps the acknowledgment banner.
public enum VendorShiftNotifier {

    private static let logger = Logger(
        subsystem: "com.shift.cloudkit",
        category: "VendorShiftNotifier"
    )

    /// Resets all vendor acknowledgment flags and stamps `pendingShiftDelta`.
    ///
    /// Call after `RippleEngine.recalculate()` succeeds and before
    /// `modelContext.save()` so the reset is atomic with the shift persist.
    ///
    /// - Parameters:
    ///   - event: The event whose vendors to evaluate.
    ///   - blocks: The blocks after the engine has mutated them.
    public static func applyThresholdNotifications(
        event: EventModel,
        blocks: [TimeBlockModel]
    ) {
        // Compute per-block deltas (how much each block actually moved).
        var blockDeltas: [UUID: TimeInterval] = [:]
        for block in blocks {
            let actualDelta = block.scheduledStart.timeIntervalSince1970
                - block.originalStart.timeIntervalSince1970
            if abs(actualDelta) > 0 {
                blockDeltas[block.id] = actualDelta
            }
        }

        guard !blockDeltas.isEmpty else { return }

        let allVendors = event.vendors ?? []
        let eventMaxDelta = blockDeltas.values
            .max(by: { abs($0) < abs($1) }) ?? 0

        // Phase 1: Reset ALL vendors atomically — a new shift invalidates
        // every prior acknowledgment regardless of threshold.
        for vendor in allVendors {
            vendor.hasAcknowledgedLatestShift = false
            vendor.pendingShiftDelta = eventMaxDelta
        }

        // Phase 2: Evaluate per-vendor thresholds. Vendors with assigned
        // blocks that shifted get their own precise delta; the threshold
        // flag is used by VendorShiftLocalNotifier to decide whether to
        // post a visible push notification.
        let decisions = VendorNotificationEvaluator.evaluate(
            event: event,
            shiftedBlockDeltas: blockDeltas
        )

        for decision in decisions {
            guard let vendor = allVendors.first(where: { $0.id == decision.vendorID }) else {
                continue
            }

            // Overwrite with the vendor-specific max delta for precision.
            vendor.pendingShiftDelta = decision.maxDelta

            if decision.shouldNotifyVisibly {
                logger.info(
                    "Vendor \(vendor.name): shift \(Int(decision.maxDelta / 60))min >= threshold \(Int(decision.threshold / 60))min — visible notification"
                )
            } else {
                logger.info(
                    "Vendor \(vendor.name): shift \(Int(decision.maxDelta / 60))min < threshold \(Int(decision.threshold / 60))min — silent only"
                )
            }
        }
    }
}
