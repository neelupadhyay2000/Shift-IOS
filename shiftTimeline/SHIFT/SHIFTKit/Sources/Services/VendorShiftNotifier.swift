import Foundation
import Models
import os

/// After the planner commits a shift, this helper evaluates each vendor's
/// notification threshold and stamps `pendingShiftDelta` on vendors whose
/// assigned blocks shifted enough to warrant a visible notification.
///
/// The `pendingShiftDelta` value syncs to the vendor's device via CloudKit,
/// where it triggers a local notification. Vendors below threshold still
/// receive the data via silent sync — they just don't get an alert.
public enum VendorShiftNotifier {

    private static let logger = Logger(
        subsystem: "com.shift.cloudkit",
        category: "VendorShiftNotifier"
    )

    /// Evaluates threshold logic and stamps `pendingShiftDelta` on qualifying vendors.
    ///
    /// Call after `RippleEngine.recalculate()` succeeds and before `modelContext.save()`.
    ///
    /// - Parameters:
    ///   - event: The event whose vendors to evaluate.
    ///   - blocks: The blocks after the engine has mutated them.
    ///   - delta: The original shift delta (seconds) requested by the planner.
    public static func applyThresholdNotifications(
        event: EventModel,
        blocks: [TimeBlockModel],
        delta: TimeInterval
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

        let decisions = VendorNotificationEvaluator.evaluate(
            event: event,
            shiftedBlockDeltas: blockDeltas
        )

        for decision in decisions {
            guard let vendor = (event.vendors ?? []).first(where: { $0.id == decision.vendorID }) else {
                continue
            }

            if decision.shouldNotifyVisibly {
                vendor.pendingShiftDelta = decision.maxDelta
                vendor.hasAcknowledgedLatestShift = false
                logger.info(
                    "Vendor \(vendor.name): shift \(Int(decision.maxDelta / 60))min >= threshold \(Int(decision.threshold / 60))min — visible notification"
                )
            } else {
                // Below threshold — clear any stale pending alert, silent sync suffices.
                vendor.pendingShiftDelta = nil
                logger.info(
                    "Vendor \(vendor.name): shift \(Int(decision.maxDelta / 60))min < threshold \(Int(decision.threshold / 60))min — silent only"
                )
            }
        }
    }
}
