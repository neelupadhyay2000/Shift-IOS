import Foundation
import Models
import Services
import Testing

@Suite("Vendor Notification Threshold")
struct VendorNotificationThresholdTests {

    // MARK: - Default Threshold

    @Test func defaultThresholdIsTenMinutes() {
        let vendor = VendorModel(name: "DJ Mike", role: .dj)
        #expect(vendor.notificationThreshold == 600) // 10 minutes
    }

    // MARK: - Evaluator: Above Threshold → Visible

    @Test func visibleNotificationWhenDeltaExceedsThreshold() {
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        let vendor = VendorModel(name: "DJ Mike", role: .dj)
        vendor.notificationThreshold = 600 // 10 min

        let block = TimeBlockModel(
            title: "DJ Set",
            scheduledStart: .now,
            duration: 3600,
            isPinned: false
        )
        vendor.assignedBlocks = [block]
        event.vendors = [vendor]

        // Block shifted by 15 minutes
        let deltas: [UUID: TimeInterval] = [block.id: 900]
        let decisions = VendorNotificationEvaluator.evaluate(
            event: event,
            shiftedBlockDeltas: deltas
        )

        #expect(decisions.count == 1)
        #expect(decisions[0].shouldNotifyVisibly == true)
        #expect(decisions[0].maxDelta == 900)
    }

    // MARK: - Evaluator: Below Threshold → Silent

    @Test func silentOnlyWhenDeltaBelowThreshold() {
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        let vendor = VendorModel(name: "Photographer", role: .photographer)
        vendor.notificationThreshold = 600 // 10 min

        let block = TimeBlockModel(
            title: "Photos",
            scheduledStart: .now,
            duration: 3600,
            isPinned: false
        )
        vendor.assignedBlocks = [block]
        event.vendors = [vendor]

        // Block shifted by only 5 minutes
        let deltas: [UUID: TimeInterval] = [block.id: 300]
        let decisions = VendorNotificationEvaluator.evaluate(
            event: event,
            shiftedBlockDeltas: deltas
        )

        #expect(decisions.count == 1)
        #expect(decisions[0].shouldNotifyVisibly == false)
        #expect(decisions[0].maxDelta == 300)
    }

    // MARK: - Evaluator: Exact Threshold → Visible

    @Test func visibleNotificationWhenDeltaEqualsThreshold() {
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        let vendor = VendorModel(name: "Florist", role: .florist)
        vendor.notificationThreshold = 600

        let block = TimeBlockModel(
            title: "Flowers",
            scheduledStart: .now,
            duration: 3600,
            isPinned: false
        )
        vendor.assignedBlocks = [block]
        event.vendors = [vendor]

        // Exactly at threshold
        let deltas: [UUID: TimeInterval] = [block.id: 600]
        let decisions = VendorNotificationEvaluator.evaluate(
            event: event,
            shiftedBlockDeltas: deltas
        )

        #expect(decisions.count == 1)
        #expect(decisions[0].shouldNotifyVisibly == true)
    }

    // MARK: - Per-Vendor Thresholds

    @Test func perVendorThresholdEvaluation() {
        let event = EventModel(title: "Concert", date: .now, latitude: 0, longitude: 0)

        let dj = VendorModel(name: "DJ", role: .dj)
        dj.notificationThreshold = 300 // 5 min — low threshold

        let caterer = VendorModel(name: "Caterer", role: .caterer)
        caterer.notificationThreshold = 900 // 15 min — high threshold

        let block1 = TimeBlockModel(
            title: "DJ Set",
            scheduledStart: .now,
            duration: 3600,
            isPinned: false
        )
        let block2 = TimeBlockModel(
            title: "Dinner",
            scheduledStart: .now,
            duration: 3600,
            isPinned: false
        )

        dj.assignedBlocks = [block1]
        caterer.assignedBlocks = [block2]
        event.vendors = [dj, caterer]

        // Both blocks shifted by 8 minutes
        let deltas: [UUID: TimeInterval] = [
            block1.id: 480,
            block2.id: 480,
        ]

        let decisions = VendorNotificationEvaluator.evaluate(
            event: event,
            shiftedBlockDeltas: deltas
        )

        #expect(decisions.count == 2)

        let djDecision = decisions.first { $0.vendorName == "DJ" }
        let catererDecision = decisions.first { $0.vendorName == "Caterer" }

        // DJ: 480s >= 300s threshold → visible
        #expect(djDecision?.shouldNotifyVisibly == true)
        // Caterer: 480s < 900s threshold → silent
        #expect(catererDecision?.shouldNotifyVisibly == false)
    }

    // MARK: - Vendor With No Affected Blocks

    @Test func vendorWithNoAffectedBlocksIsExcluded() {
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        let vendor = VendorModel(name: "DJ", role: .dj)

        let assignedBlock = TimeBlockModel(
            title: "DJ Set",
            scheduledStart: .now,
            duration: 3600,
            isPinned: false
        )
        let unrelatedBlock = TimeBlockModel(
            title: "Ceremony",
            scheduledStart: .now,
            duration: 1800,
            isPinned: false
        )

        vendor.assignedBlocks = [assignedBlock]
        event.vendors = [vendor]

        // Only the unrelated block shifted
        let deltas: [UUID: TimeInterval] = [unrelatedBlock.id: 900]
        let decisions = VendorNotificationEvaluator.evaluate(
            event: event,
            shiftedBlockDeltas: deltas
        )

        // Vendor's block wasn't shifted — no decision for them
        #expect(decisions.isEmpty)
    }

    // MARK: - Multiple Blocks, Max Delta Used

    @Test func maxDeltaAcrossMultipleBlocksIsUsed() {
        let event = EventModel(title: "Conference", date: .now, latitude: 0, longitude: 0)
        let vendor = VendorModel(name: "AV Tech", role: .custom)
        vendor.notificationThreshold = 600

        let block1 = TimeBlockModel(
            title: "Keynote",
            scheduledStart: .now,
            duration: 3600,
            isPinned: false
        )
        let block2 = TimeBlockModel(
            title: "Panel",
            scheduledStart: .now,
            duration: 3600,
            isPinned: false
        )

        vendor.assignedBlocks = [block1, block2]
        event.vendors = [vendor]

        // block1 shifted 3 min, block2 shifted 12 min
        let deltas: [UUID: TimeInterval] = [
            block1.id: 180,
            block2.id: 720,
        ]

        let decisions = VendorNotificationEvaluator.evaluate(
            event: event,
            shiftedBlockDeltas: deltas
        )

        #expect(decisions.count == 1)
        // Max delta is 720s (12 min) >= 600s threshold → visible
        #expect(decisions[0].maxDelta == 720)
        #expect(decisions[0].shouldNotifyVisibly == true)
    }

    // MARK: - No Vendors

    @Test func noVendorsReturnsEmptyDecisions() {
        let event = EventModel(title: "Solo Event", date: .now, latitude: 0, longitude: 0)
        event.vendors = []

        let deltas: [UUID: TimeInterval] = [UUID(): 900]
        let decisions = VendorNotificationEvaluator.evaluate(
            event: event,
            shiftedBlockDeltas: deltas
        )

        #expect(decisions.isEmpty)
    }

    // MARK: - Custom Threshold

    @Test func vendorCanSetCustomThreshold() {
        let vendor = VendorModel(name: "Custom", role: .custom)
        vendor.notificationThreshold = 1800 // 30 minutes

        #expect(vendor.notificationThreshold == 1800)
    }
}
