import Foundation
import SwiftData
import Testing
@testable import Models
import Services
import TestSupport

/// SHIFT-1002.5 — Asserts each `TestFixture` builder seeds the expected
/// data graph (counts, titles, statuses, weather, sunset markers) into a
/// fresh in-memory `ModelContainer`.
///
/// All tests pin time to `TestClock.reference` (2025-06-15T12:00:00Z) so
/// fixture output is identical across machines and CI runs.
///
/// `.serialized` matches the convention used by other SwiftData-backed
/// suites in this target (e.g. `WatchSessionManagerTests`,
/// `SunsetServiceTests`) — Swift Testing's default parallelism plus
/// per-test in-memory `ModelContainer` instances has caused intermittent
/// SwiftData crashes when multiple containers initialise concurrently.
@Suite("TestFixture builders seed deterministic data", .serialized)
struct TestFixtureBuildersTests {

    // MARK: - singleEventFiveBlocks

    @Test @MainActor
    func singleEventFiveBlocks() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        try TestFixture.singleEventFiveBlocks.build(into: context, clock: .reference)
        try context.save()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        let tracks = try context.fetch(FetchDescriptor<TimelineTrack>())
        let blocks = try context.fetch(
            FetchDescriptor<TimeBlockModel>(sortBy: [SortDescriptor(\.scheduledStart)])
        )

        #expect(events.count == 1)
        #expect(tracks.count == 1)
        #expect(blocks.count == 5)
        #expect(blocks.map(\.title) == ["Welcome & Intro", "Session 1", "Break", "Session 2", "Wrap-Up"])
        #expect(blocks.allSatisfy { $0.duration == 1800 })

        let base = TestClock.reference.now
        for (index, block) in blocks.enumerated() {
            #expect(block.scheduledStart == base.addingTimeInterval(Double(index) * 1800))
        }
    }

    // MARK: - weddingTemplateApplied

    @Test @MainActor
    func weddingTemplateApplied() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        try TestFixture.weddingTemplateApplied.build(into: context, clock: .reference)
        try context.save()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        let blocks = try context.fetch(FetchDescriptor<TimeBlockModel>())

        #expect(events.count == 1)
        #expect(blocks.count == 15)

        let pinned = blocks.filter(\.isPinned)
        #expect(pinned.count == 1)
        #expect(pinned.first?.title == "Ceremony")
    }

    // MARK: - multiTrackConference

    @Test @MainActor
    func multiTrackConference() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        try TestFixture.multiTrackConference.build(into: context, clock: .reference)
        try context.save()

        let tracks = try context.fetch(
            FetchDescriptor<TimelineTrack>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        let blocks = try context.fetch(FetchDescriptor<TimeBlockModel>())

        #expect(tracks.map(\.name) == ["Main", "Ceremony", "Reception"])
        #expect(blocks.count == 7)

        let mainCount = blocks.filter { $0.track?.name == "Main" }.count
        let ceremonyCount = blocks.filter { $0.track?.name == "Ceremony" }.count
        let receptionCount = blocks.filter { $0.track?.name == "Reception" }.count
        #expect(mainCount == 3)
        #expect(ceremonyCount == 2)
        #expect(receptionCount == 2)
    }

    // MARK: - eventWithVendors(count:)

    @Test @MainActor
    func eventWithVendors() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        try TestFixture.eventWithVendors(count: 3).build(into: context, clock: .reference)
        try context.save()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        let vendors = try context.fetch(
            FetchDescriptor<VendorModel>(sortBy: [SortDescriptor(\.name)])
        )

        #expect(events.count == 1)
        #expect(vendors.count == 3)
        #expect(vendors.allSatisfy { $0.event?.id == events.first?.id })

        let roles = VendorRole.allCases
        for (index, vendor) in vendors.enumerated() {
            #expect(vendor.role == roles[index % roles.count])
        }
    }

    @Test @MainActor
    func eventWithVendorsZero() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        try TestFixture.eventWithVendors(count: 0).build(into: context, clock: .reference)
        try context.save()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        let vendors = try context.fetch(FetchDescriptor<VendorModel>())

        #expect(events.count == 1)
        #expect(vendors.isEmpty)
    }

    // MARK: - liveEventInProgress(blockIndex:)

    @Test @MainActor
    func liveEventInProgress() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        try TestFixture.liveEventInProgress(blockIndex: 2).build(into: context, clock: .reference)
        try context.save()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        let blocks = try context.fetch(
            FetchDescriptor<TimeBlockModel>(sortBy: [SortDescriptor(\.scheduledStart)])
        )

        #expect(events.first?.status == .live)
        #expect(blocks.count == 5)

        let statuses = blocks.map(\.status)
        #expect(statuses == [.completed, .completed, .active, .upcoming, .upcoming])
    }

    // MARK: - eventWithRainForecastedBlock

    @Test @MainActor
    func eventWithRainForecastedBlock() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        try TestFixture.eventWithRainForecastedBlock.build(into: context, clock: .reference)
        try context.save()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        let blocks = try context.fetch(FetchDescriptor<TimeBlockModel>())

        #expect(blocks.count == 1)
        let block = try #require(blocks.first)
        #expect(block.isOutdoor)

        let snapshotData = try #require(events.first?.weatherSnapshot)
        let snapshot = try JSONDecoder().decode(WeatherSnapshot.self, from: snapshotData)
        #expect(snapshot.entries.count == 1)
        let entry = try #require(snapshot.entries.first)
        #expect(entry.blockId == block.id)
        #expect(entry.rainProbability == 0.8)
    }

    // MARK: - eventWithSunsetBlocks

    @Test @MainActor
    func eventWithSunsetBlocks() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        try TestFixture.eventWithSunsetBlocks.build(into: context, clock: .reference)
        try context.save()

        let events = try context.fetch(FetchDescriptor<EventModel>())
        let blocks = try context.fetch(
            FetchDescriptor<TimeBlockModel>(sortBy: [SortDescriptor(\.scheduledStart)])
        )

        let event = try #require(events.first)
        let base = TestClock.reference.now
        #expect(event.goldenHourStart == base.addingTimeInterval(7.5 * 3600))
        #expect(event.sunsetTime == base.addingTimeInterval(8.0 * 3600))

        #expect(blocks.map(\.title) == [
            "Rooftop Cocktails",
            "Golden Hour Portraits",
            "Sunset Ceremony",
        ])
    }
}
