import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

@Suite("InitialHydrator — fetch + upsert into SwiftData")
@MainActor
struct InitialHydratorTests {

    private struct FakeHydrationSource: HydrationSource {
        let snapshot: HydrationSnapshot
        func fetchSnapshot() async throws -> HydrationSnapshot { snapshot }
    }

    private func blockDTO(id: UUID, trackID: UUID, eventID: UUID, title: String) -> BlockDTO {
        BlockDTO(
            id: id, trackID: trackID, eventID: eventID, title: title,
            scheduledStart: fixedPGTimestamp, originalStart: fixedPGTimestamp,
            duration: 1800, minimumDuration: 0, isPinned: false, notes: "",
            colorTag: "#007AFF", icon: "circle.fill", status: "upcoming",
            requiresReview: false, isOutdoor: false, venueAddress: "", venueName: "",
            isTransitBlock: false
        )
    }

    @Test("a clean install fully reconstructs the event graph from a snapshot")
    func cleanInstallReconstructsGraph() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventID = UUID(), trackID = UUID(), blockID = UUID()
        let dependencyID = UUID(), vendorID = UUID(), recordID = UUID()

        let snapshot = HydrationSnapshot(
            events: [EventDTO(id: eventID, ownerID: UUID(), title: "Gala", date: fixedPGTimestamp, status: "planning")],
            tracks: [TrackDTO(id: trackID, eventID: eventID, name: "Main", sortOrder: 0, isDefault: true)],
            blocks: [
                blockDTO(id: blockID, trackID: trackID, eventID: eventID, title: "Ceremony"),
                blockDTO(id: dependencyID, trackID: trackID, eventID: eventID, title: "Setup"),
            ],
            vendors: [EventVendorDTO(
                id: vendorID, eventID: eventID, displayName: "DJ", role: "dj",
                notificationThreshold: 600, hasAcknowledgedLatestShift: false
            )],
            blockVendors: [BlockVendorDTO(blockID: blockID, eventVendorID: vendorID, eventID: eventID)],
            blockDependencies: [BlockDependencyDTO(blockID: blockID, dependsOnBlockID: dependencyID, eventID: eventID)],
            shiftRecords: [ShiftRecordDTO(
                id: recordID, eventID: eventID, sourceBlockID: blockID,
                timestamp: fixedPGTimestamp, deltaMinutes: 5, triggeredBy: "manual"
            )]
        )

        let hydrator = InitialHydrator(source: FakeHydrationSource(snapshot: snapshot), context: context)
        try await hydrator.hydrate()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.id == eventID)
        #expect(event.title == "Gala")
        #expect(event.tracks?.count == 1)
        #expect(event.vendors?.map(\.id) == [vendorID])
        #expect(event.shiftRecords?.count == 1)

        let track = try #require(event.tracks?.first)
        #expect(track.id == trackID)
        #expect(track.blocks?.count == 2)

        let block = try #require(track.blocks?.first { $0.id == blockID })
        #expect(block.vendors?.map(\.id) == [vendorID])
        #expect(block.dependencies?.map(\.id) == [dependencyID])

        let record = try #require(event.shiftRecords?.first)
        #expect(record.event?.id == eventID)
        #expect(record.sourceBlock?.id == blockID)
    }

    @Test("upsert updates an existing row by id instead of duplicating it")
    func upsertUpdatesExistingByID() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let eventID = UUID()
        let existing = EventModel(id: eventID, title: "Old", date: fixedTimestamp, latitude: 0, longitude: 0)
        context.insert(existing)
        try context.save()

        let snapshot = HydrationSnapshot(
            events: [EventDTO(id: eventID, ownerID: UUID(), title: "New", date: fixedPGTimestamp, status: "live")]
        )
        let hydrator = InitialHydrator(source: FakeHydrationSource(snapshot: snapshot), context: context)
        try await hydrator.hydrate()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        #expect(events.count == 1)              // updated in place, not duplicated
        #expect(events.first?.id == eventID)
        #expect(events.first?.title == "New")
        #expect(events.first?.status == .live)
    }

    @Test("an empty snapshot leaves the store empty without error")
    func emptySnapshot() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let hydrator = InitialHydrator(source: FakeHydrationSource(snapshot: HydrationSnapshot()), context: context)

        try await hydrator.hydrate()

        #expect(try context.fetch(FetchDescriptor<EventModel>()).isEmpty)
    }
}
