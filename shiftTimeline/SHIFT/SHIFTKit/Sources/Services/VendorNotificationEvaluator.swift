import Foundation
import Models

/// Evaluates each vendor's notification threshold against the shift delta
/// to decide whether a visible push notification is warranted.
///
/// **Pure logic** — no side effects. Call sites decide how to dispatch
/// the resulting decisions (e.g. set a flag on the model for CloudKit sync).
public enum VendorNotificationEvaluator {

    /// The notification decision for a single vendor after a shift.
    public struct Decision: Sendable, Equatable {
        public let vendorID: UUID
        public let vendorName: String
        /// The largest absolute shift delta (seconds) across the vendor's assigned blocks.
        public let maxDelta: TimeInterval
        /// The vendor's configured threshold (seconds).
        public let threshold: TimeInterval
        /// `true` when the shift warrants a visible notification.
        public var shouldNotifyVisibly: Bool { abs(maxDelta) >= threshold }
    }

    /// Evaluates every vendor on the event, comparing each vendor's maximum
    /// block-shift delta against their personal `notificationThreshold`.
    ///
    /// - Parameters:
    ///   - event: The event whose vendors to evaluate.
    ///   - shiftedBlockDeltas: A dictionary mapping each shifted block's ID
    ///     to its delta (seconds). Typically computed as
    ///     `block.scheduledStart - block.originalStart` after the engine runs.
    /// - Returns: One ``Decision`` per vendor that has at least one assigned
    ///   block affected by the shift.
    public static func evaluate(
        event: EventModel,
        shiftedBlockDeltas: [UUID: TimeInterval]
    ) -> [Decision] {
        guard let vendors = event.vendors, !vendors.isEmpty else { return [] }

        var decisions: [Decision] = []

        for vendor in vendors {
            let assignedBlockIDs = Set((vendor.assignedBlocks ?? []).map(\.id))
            // Find the largest absolute delta among this vendor's assigned blocks.
            let relevantDeltas = shiftedBlockDeltas.filter { assignedBlockIDs.contains($0.key) }
            guard !relevantDeltas.isEmpty else { continue }

            let maxDelta = relevantDeltas.values
                .max(by: { abs($0) < abs($1) }) ?? 0

            decisions.append(Decision(
                vendorID: vendor.id,
                vendorName: vendor.name,
                maxDelta: maxDelta,
                threshold: vendor.notificationThreshold
            ))
        }

        return decisions
    }
}
