import Foundation
import Models
import os

/// Resets vendor acknowledgment flags and stamps `pendingShiftDelta` after a shift commit.
public enum VendorShiftNotifier {

    private static let logger = Logger(
        subsystem: "com.shift.cloudkit",
        category: "VendorShiftNotifier"
    )

    /// Resets all vendor ack flags and stamps `pendingShiftDelta`. Call after ripple, before `context.save()`.
    public static func applyThresholdNotifications(
        event: EventModel,
        blocks: [TimeBlockModel]
    ) {
        // Compute per-block deltas.
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

        // Phase 1: Reset ALL vendors — new shift invalidates all prior acks.
        for vendor in allVendors {
            vendor.hasAcknowledgedLatestShift = false
            vendor.pendingShiftDelta = eventMaxDelta
        }

        // Phase 2: Evaluate per-vendor thresholds for precise delta and notification decision.
        let decisions = VendorNotificationEvaluator.evaluate(
            event: event,
            shiftedBlockDeltas: blockDeltas
        )

        for decision in decisions {
            guard let vendor = allVendors.first(where: { $0.id == decision.vendorID }) else {
                continue
            }

            // Overwrite with vendor-specific max delta.
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
