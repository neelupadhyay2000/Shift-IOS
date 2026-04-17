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

    @Test func isOwnedByReturnsTrueWhenCurrentUserIsNil() {
        // iCloud unavailable — treat as owned to avoid locking out
        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        event.ownerRecordName = "user_abc"

        #expect(event.isOwnedBy(nil) == true)
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
