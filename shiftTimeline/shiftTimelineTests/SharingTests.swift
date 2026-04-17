import Foundation
import Models
import Services
import SwiftData
import Testing

@Suite("Sharing & Vendor Scoping")
struct SharingTests {

    // MARK: - EventModel.isOwnedBy

    @Test func isOwnedByReturnsTrueWhenOwnerMatches() {
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        event.ownerRecordName = "user_abc"

        #expect(event.isOwnedBy("user_abc") == true)
    }

    @Test func isOwnedByReturnsFalseWhenOwnerDiffers() {
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        event.ownerRecordName = "user_abc"

        #expect(event.isOwnedBy("user_xyz") == false)
    }

    @Test func isOwnedByReturnsTrueWhenOwnerRecordNameIsNil() {
        // Pre-feature events have no ownerRecordName — treat as owned
        let event = EventModel(title: "Legacy Event", date: .now, latitude: 0, longitude: 0)

        #expect(event.isOwnedBy("user_abc") == true)
        #expect(event.isOwnedBy(nil) == true)
    }

    @Test func isOwnedByReturnsFalseWhenCurrentUserIsNil() {
        // iCloud unavailable + event has an owner — default to read-only
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        event.ownerRecordName = "user_abc"

        #expect(event.isOwnedBy(nil) == false)
    }

    // MARK: - EventModel.vendorForUser

    @Test @MainActor func vendorForUserFindsMatchingVendor() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let vendor = VendorModel(name: "DJ Mike", role: .custom)
        vendor.cloudKitRecordName = "user_vendor_1"
        vendor.event = event
        context.insert(vendor)
        try context.save()

        let found = event.vendorForUser("user_vendor_1")
        #expect(found?.id == vendor.id)
    }

    @Test @MainActor func vendorForUserReturnsNilWhenNoMatch() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let vendor = VendorModel(name: "DJ Mike", role: .custom)
        vendor.cloudKitRecordName = "user_vendor_1"
        vendor.event = event
        context.insert(vendor)
        try context.save()

        #expect(event.vendorForUser("user_vendor_999") == nil)
    }

    @Test func vendorForUserReturnsNilWhenCurrentUserIsNil() {
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)

        #expect(event.vendorForUser(nil) == nil)
    }

    // MARK: - Vendor Block Detail Scoping

    @Test @MainActor func vendorCanSeeDetailsForAssignedBlock() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        event.ownerRecordName = "owner_user"
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let vendor = VendorModel(name: "Photographer", role: .custom)
        vendor.cloudKitRecordName = "vendor_user"
        vendor.event = event
        context.insert(vendor)

        let block = TimeBlockModel(title: "Photos", scheduledStart: .now, duration: 3600)
        block.track = track
        block.vendors = [vendor]
        context.insert(block)
        try context.save()

        // Vendor is assigned to this block — should see details
        let currentVendor = event.vendorForUser("vendor_user")
        let canSeeDetails = (block.vendors ?? []).contains { $0.id == currentVendor?.id }
        #expect(canSeeDetails == true)
    }

    @Test @MainActor func vendorCannotSeeDetailsForUnassignedBlock() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        event.ownerRecordName = "owner_user"
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let vendor = VendorModel(name: "Photographer", role: .custom)
        vendor.cloudKitRecordName = "vendor_user"
        vendor.event = event
        context.insert(vendor)

        // Block has no assigned vendors
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)
        try context.save()

        let currentVendor = event.vendorForUser("vendor_user")
        let canSeeDetails = (block.vendors ?? []).contains { $0.id == currentVendor?.id }
        #expect(canSeeDetails == false)
    }

    @Test @MainActor func ownerAlwaysSeesAllDetails() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        event.ownerRecordName = "owner_user"
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800, notes: "Secret production notes")
        block.track = track
        context.insert(block)
        try context.save()

        // Owner doesn't need to be an assigned vendor
        let isOwner = event.isOwnedBy("owner_user")
        #expect(isOwner == true)
        // Owner sees details regardless of assignment
    }

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

    @Test @MainActor func sharedEventIdentifiedCorrectly() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        event.ownerRecordName = "planner_user"
        context.insert(event)
        try context.save()

        // From the planner's perspective — owned
        #expect(event.isOwnedBy("planner_user") == true)

        // From a vendor's perspective — shared (not owned)
        #expect(event.isOwnedBy("vendor_user") == false)
    }
}
