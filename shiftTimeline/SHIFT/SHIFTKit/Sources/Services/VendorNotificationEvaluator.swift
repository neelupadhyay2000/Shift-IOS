import Foundation
import Models

/// Pure logic — evaluates each vendor's notification threshold against the shift delta.
public enum VendorNotificationEvaluator {

    /// The notification decision for a single vendor after a shift.
    public struct Decision: Sendable, Equatable {
        public let vendorID: UUID
        public let vendorName: String
        public let maxDelta: TimeInterval   // largest absolute delta (seconds) across assigned blocks
        public let threshold: TimeInterval  // vendor-configured threshold (seconds)
        public var shouldNotifyVisibly: Bool { abs(maxDelta) >= threshold }
    }

    /// Returns one `Decision` per vendor with at least one assigned block shifted.
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
