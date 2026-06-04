import Foundation
import Models
import Services
import SwiftData
import Testing

@Suite("Sharing & Vendor Scoping")
struct SharingTests {

    // MARK: - Atomic Ack Reset on New Shift

    /// Helper: creates a block whose `scheduledStart` is `deltaSeconds` ahead
    /// of its `originalStart`, so `VendorShiftNotifier` computes the expected delta.
    private static func shiftedBlock(
        title: String = "Block",
        deltaSeconds: TimeInterval
    ) -> TimeBlockModel {
        let origin = Date.now
        return TimeBlockModel(
            title: title,
            scheduledStart: origin.addingTimeInterval(deltaSeconds),
            originalStart: origin,
            duration: 3600,
            isPinned: false
        )
    }

    @Test func newShiftResetsAllVendorAckFlags() {
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)

        // 5 vendors — some previously acknowledged, some not
        let vendors = (0..<5).map { i in
            let v = VendorModel(name: "Vendor \(i)", role: .custom)
            v.event = event
            return v
        }
        vendors[0].hasAcknowledgedLatestShift = true
        vendors[1].hasAcknowledgedLatestShift = true
        vendors[2].hasAcknowledgedLatestShift = false
        vendors[3].hasAcknowledgedLatestShift = true
        vendors[4].hasAcknowledgedLatestShift = false
        event.vendors = vendors

        let block = Self.shiftedBlock(title: "Ceremony", deltaSeconds: 900)
        vendors[0].assignedBlocks = [block]

        VendorShiftNotifier.applyThresholdNotifications(
            event: event,
            blocks: [block]
        )

        // ALL vendors must be pending — even those previously acknowledged
        for vendor in vendors {
            #expect(
                vendor.hasAcknowledgedLatestShift == false,
                "Vendor \(vendor.name) should be reset to pending"
            )
            #expect(
                vendor.pendingShiftDelta != nil,
                "Vendor \(vendor.name) should have pendingShiftDelta set"
            )
        }
    }

    @Test func newShiftSetsEventLevelDeltaOnUnassignedVendors() {
        let event = EventModel(title: "Gala", date: .now, latitude: 0, longitude: 0)

        let assignedVendor = VendorModel(name: "DJ", role: .dj)
        let unassignedVendor = VendorModel(name: "Florist", role: .florist)
        assignedVendor.event = event
        unassignedVendor.event = event
        event.vendors = [assignedVendor, unassignedVendor]

        let block = Self.shiftedBlock(title: "Set", deltaSeconds: 900)
        assignedVendor.assignedBlocks = [block]

        VendorShiftNotifier.applyThresholdNotifications(
            event: event,
            blocks: [block]
        )

        // Assigned vendor gets their precise delta
        #expect(assignedVendor.pendingShiftDelta == 900)
        // Unassigned vendor gets the event-level max delta
        #expect(unassignedVendor.pendingShiftDelta == 900)
    }

    @Test func previouslyAcknowledgedVendorsShowPendingAfterNewShift() {
        let event = EventModel(title: "Concert", date: .now, latitude: 0, longitude: 0)

        let vendor = VendorModel(name: "Sound Tech", role: .custom)
        vendor.hasAcknowledgedLatestShift = true
        vendor.pendingShiftDelta = nil
        vendor.event = event
        event.vendors = [vendor]

        let block = Self.shiftedBlock(title: "Soundcheck", deltaSeconds: 600)
        vendor.assignedBlocks = [block]

        VendorShiftNotifier.applyThresholdNotifications(
            event: event,
            blocks: [block]
        )

        #expect(vendor.hasAcknowledgedLatestShift == false)
        #expect(vendor.pendingShiftDelta == 600)
    }
}
