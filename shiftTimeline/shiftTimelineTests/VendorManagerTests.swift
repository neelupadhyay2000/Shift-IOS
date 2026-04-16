import Foundation
import Models
import Services
import SwiftData
import Testing
@testable import shiftTimeline

struct VendorManagerTests {

    // MARK: - Save (mirrors VendorFormSheet.saveVendor)

    @Test @MainActor func saveVendorTrimsWhitespaceAndAttachesToEvent() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        try context.save()

        // Simulate VendorFormSheet.saveVendor() with padded input
        let vendor = VendorModel(
            name: "  Jane Smith  ".trimmingCharacters(in: .whitespaces),
            role: .photographer,
            phone: " 555-0100 ".trimmingCharacters(in: .whitespaces),
            email: " jane@example.com ".trimmingCharacters(in: .whitespaces)
        )
        vendor.event = event
        context.insert(vendor)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<VendorModel>())
        let result = try #require(fetched.first)

        #expect(result.name == "Jane Smith")
        #expect(result.phone == "555-0100")
        #expect(result.email == "jane@example.com")
        #expect(result.role == .photographer)
        #expect(result.event === event)
        #expect((event.vendors ?? []).count == 1)
    }

    @Test @MainActor func saveVendorWithEmptyContactFieldsSucceeds() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Gala", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let vendor = VendorModel(name: "DJ Mike", role: .dj)
        vendor.event = event
        context.insert(vendor)
        try context.save()

        let result = try #require(try context.fetch(FetchDescriptor<VendorModel>()).first)
        #expect(result.phone == "")
        #expect(result.email == "")
        #expect(result.event === event)
    }

    // MARK: - Delete (mirrors VendorManagerView.deleteVendors)

    @Test @MainActor func deleteVendorsByOffsetFromSortedList() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Concert", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let v1 = VendorModel(name: "Charlie", role: .caterer)
        let v2 = VendorModel(name: "Alice", role: .florist)
        let v3 = VendorModel(name: "Bob", role: .dj)
        for v in [v1, v2, v3] {
            v.event = event
            context.insert(v)
        }
        try context.save()
        #expect((event.vendors ?? []).count == 3)

        // Mirror VendorManagerView.deleteVendors: sort by name, then delete by offset
        let sorted = (event.vendors ?? []).sorted(by: { $0.name < $1.name })
        // sorted order: Alice (0), Bob (1), Charlie (2)
        #expect(sorted[0].name == "Alice")
        #expect(sorted[1].name == "Bob")
        #expect(sorted[2].name == "Charlie")

        // Delete index 1 (Bob)
        let offsets = IndexSet(integer: 1)
        for index in offsets {
            context.delete(sorted[index])
        }
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<VendorModel>())
        #expect(remaining.count == 2)
        #expect(remaining.contains(where: { $0.name == "Alice" }))
        #expect(remaining.contains(where: { $0.name == "Charlie" }))
        #expect(!remaining.contains(where: { $0.name == "Bob" }))
    }

    @Test @MainActor func deleteMultipleVendorsByOffsets() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Retreat", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let names = ["Delta", "Alpha", "Echo", "Bravo", "Charlie"]
        for name in names {
            let v = VendorModel(name: name, role: .planner)
            v.event = event
            context.insert(v)
        }
        try context.save()

        let sorted = (event.vendors ?? []).sorted(by: { $0.name < $1.name })
        // sorted: Alpha(0), Bravo(1), Charlie(2), Delta(3), Echo(4)

        // Delete indices 0 and 3 (Alpha and Delta)
        var offsets = IndexSet()
        offsets.insert(0)
        offsets.insert(3)
        for index in offsets {
            context.delete(sorted[index])
        }
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<VendorModel>())
        #expect(remaining.count == 3)
        let remainingNames = Set(remaining.map(\.name))
        #expect(remainingNames == ["Bravo", "Charlie", "Echo"])
    }

    // MARK: - Sorted display order

    @Test @MainActor func vendorsAreSortedByNameAlphabetically() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Fair", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        for name in ["Zara", "Mike", "Anna"] {
            let v = VendorModel(name: name, role: .custom)
            v.event = event
            context.insert(v)
        }
        try context.save()

        let sorted = (event.vendors ?? []).sorted(by: { $0.name < $1.name })
        #expect(sorted.map(\.name) == ["Anna", "Mike", "Zara"])
    }

    // MARK: - VendorRole display extensions

    @Test func vendorRoleDisplayNameCoversAllCases() {
        let expected: [VendorRole: String] = [
            .photographer: "Photographer",
            .dj: "DJ",
            .planner: "Planner",
            .caterer: "Caterer",
            .florist: "Florist",
            .custom: "Custom",
        ]
        for (role, name) in expected {
            #expect(role.displayName == name)
        }
    }

    @Test func vendorRoleSystemImageCoversAllCases() {
        let expected: [VendorRole: String] = [
            .photographer: "camera.fill",
            .dj: "music.note",
            .planner: "clipboard.fill",
            .caterer: "fork.knife",
            .florist: "leaf.fill",
            .custom: "person.fill",
        ]
        for (role, image) in expected {
            #expect(role.systemImage == image)
        }
    }

    // MARK: - Edit (mirrors VendorFormSheet edit mode)

    @Test @MainActor func editVendorUpdatesAllFields() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let vendor = VendorModel(name: "Jane", role: .photographer, phone: "555-0100", email: "jane@example.com")
        vendor.event = event
        context.insert(vendor)
        try context.save()

        // Simulate VendorFormSheet save in edit mode
        vendor.name = "Jane Updated"
        vendor.role = .planner
        vendor.phone = "555-9999"
        vendor.email = "updated@example.com"
        try context.save()

        let result = try #require(try context.fetch(FetchDescriptor<VendorModel>()).first)
        #expect(result.name == "Jane Updated")
        #expect(result.role == .planner)
        #expect(result.phone == "555-9999")
        #expect(result.email == "updated@example.com")
        #expect(result.event === event)
    }

    @Test @MainActor func editVendorDoesNotCreateDuplicate() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Gala", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let vendor = VendorModel(name: "DJ Mike", role: .dj)
        vendor.event = event
        context.insert(vendor)
        try context.save()

        // Edit in place — should NOT insert a new record
        vendor.name = "DJ Mike V2"
        try context.save()

        let all = try context.fetch(FetchDescriptor<VendorModel>())
        #expect(all.count == 1)
        #expect(all.first?.name == "DJ Mike V2")
    }

    // MARK: - Delete with block assignments

    @Test @MainActor func deleteVendorRemovesFromBlockAssignments() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Concert", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        block.track = track
        context.insert(block)

        let vendor = VendorModel(name: "Photographer", role: .photographer)
        vendor.event = event
        context.insert(vendor)
        try context.save()

        // Assign vendor to block
        block.vendors = [vendor]
        try context.save()
        #expect((block.vendors ?? []).count == 1)

        // Mirror VendorManagerView.deleteVendor: remove from blocks, then delete
        for b in (event.tracks ?? []).flatMap({ $0.blocks ?? [] }) {
            b.vendors?.removeAll(where: { $0.id == vendor.id })
        }
        context.delete(vendor)
        try context.save()

        let remainingVendors = try context.fetch(FetchDescriptor<VendorModel>())
        #expect(remainingVendors.count == 0)

        let fetchedBlock = try #require(try context.fetch(FetchDescriptor<TimeBlockModel>()).first)
        #expect((fetchedBlock.vendors ?? []).isEmpty)
    }

    @Test @MainActor func deleteVendorAssignedToMultipleBlocks() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Festival", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block1 = TimeBlockModel(title: "Setup", scheduledStart: .now, duration: 1800)
        block1.track = track
        context.insert(block1)

        let block2 = TimeBlockModel(title: "Main Event", scheduledStart: .now.addingTimeInterval(3600), duration: 3600)
        block2.track = track
        context.insert(block2)

        let vendor = VendorModel(name: "Sound Tech", role: .dj)
        vendor.event = event
        context.insert(vendor)
        try context.save()

        block1.vendors = [vendor]
        block2.vendors = [vendor]
        try context.save()

        #expect((block1.vendors ?? []).count == 1)
        #expect((block2.vendors ?? []).count == 1)

        // Delete vendor — should clear from both blocks
        for b in (event.tracks ?? []).flatMap({ $0.blocks ?? [] }) {
            b.vendors?.removeAll(where: { $0.id == vendor.id })
        }
        context.delete(vendor)
        try context.save()

        let blocks = try context.fetch(FetchDescriptor<TimeBlockModel>())
        #expect(blocks.count == 2)
        #expect(blocks.allSatisfy { ($0.vendors ?? []).isEmpty })
    }

    @Test @MainActor func vendorAssignedBlockCountIsAccurate() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Party", date: .now, latitude: 0, longitude: 0)
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        let block1 = TimeBlockModel(title: "B1", scheduledStart: .now, duration: 1800)
        block1.track = track
        context.insert(block1)

        let block2 = TimeBlockModel(title: "B2", scheduledStart: .now.addingTimeInterval(3600), duration: 1800)
        block2.track = track
        context.insert(block2)

        let block3 = TimeBlockModel(title: "B3", scheduledStart: .now.addingTimeInterval(7200), duration: 1800)
        block3.track = track
        context.insert(block3)

        let vendor = VendorModel(name: "Caterer", role: .caterer)
        vendor.event = event
        context.insert(vendor)
        try context.save()

        // Assign to 2 of 3 blocks
        block1.vendors = [vendor]
        block3.vendors = [vendor]
        try context.save()

        // Mirror VendorManagerView.assignedBlockCount
        let count = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .filter { ($0.vendors ?? []).contains(where: { $0.id == vendor.id }) }
            .count
        #expect(count == 2)
    }
}
