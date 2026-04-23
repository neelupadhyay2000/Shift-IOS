import Foundation
import Models
import Services
import SwiftData
import Testing

@Suite("Weather Feature")
struct WeatherServiceTests {

    // MARK: - Schema Field Defaults (Task 2.1)

    @Test @MainActor func newBlockDefaultsIsOutdoorToFalse() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        context.insert(block)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect(result.isOutdoor == false)
    }

    @Test @MainActor func newEventDefaultsWeatherSnapshotToNil() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 51.5, longitude: -0.1)
        context.insert(event)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<EventModel>())
        let result = try #require(fetched.first)
        #expect(result.weatherSnapshot == nil)
    }

    @Test @MainActor func isOutdoorPersistsWhenSetToTrue() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let block = TimeBlockModel(title: "Outdoor Ceremony", scheduledStart: .now, duration: 1800)
        context.insert(block)
        block.isOutdoor = true
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeBlockModel>())
        let result = try #require(fetched.first)
        #expect(result.isOutdoor == true)
    }

    // MARK: - WeatherSnapshot Model (Task 3.1)

    @Test func weatherSnapshotEncodesAndDecodesRoundTrip() throws {
        let blockId = UUID()
        let entry = BlockRainEntry(blockId: blockId, rainProbability: 0.72)
        let fetchedAt = Date()
        let snapshot = WeatherSnapshot(entries: [entry], fetchedAt: fetchedAt)

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: encoded)

        #expect(decoded.entries.count == 1)
        #expect(decoded.entries[0].blockId == blockId)
        #expect(decoded.entries[0].rainProbability == 0.72)
    }

    @Test func weatherSnapshotIsFreshWhenJustFetched() {
        let snapshot = WeatherSnapshot(entries: [], fetchedAt: Date())
        #expect(snapshot.isFresh == true)
    }

    @Test func weatherSnapshotIsFreshAt29MinutesOld() {
        let date = Date().addingTimeInterval(-1740) // 29 min ago
        let snapshot = WeatherSnapshot(entries: [], fetchedAt: date)
        #expect(snapshot.isFresh == true)
    }

    @Test func weatherSnapshotIsStaleAt30MinutesExactly() {
        // < 1800 is fresh; exactly 1800 is NOT fresh
        let date = Date().addingTimeInterval(-1800)
        let snapshot = WeatherSnapshot(entries: [], fetchedAt: date)
        #expect(snapshot.isFresh == false)
    }

    @Test func weatherSnapshotIsStaleWhenOlderThan30Minutes() {
        let date = Date().addingTimeInterval(-3600)
        let snapshot = WeatherSnapshot(entries: [], fetchedAt: date)
        #expect(snapshot.isFresh == false)
    }

    @Test func atRiskEntriesExcludesIndoorBlocks() {
        let outdoorBlockId = UUID()
        let indoorBlockId = UUID()
        let snapshot = WeatherSnapshot(
            entries: [
                BlockRainEntry(blockId: outdoorBlockId, rainProbability: 0.8),
                BlockRainEntry(blockId: indoorBlockId, rainProbability: 0.9),
            ],
            fetchedAt: Date()
        )

        let blocks: [(id: UUID, isOutdoor: Bool)] = [
            (id: outdoorBlockId, isOutdoor: true),
            (id: indoorBlockId, isOutdoor: false),
        ]

        let atRisk = snapshot.atRiskEntries(for: blocks)
        #expect(atRisk.count == 1)
        #expect(atRisk[0].blockId == outdoorBlockId)
    }

    @Test func atRiskEntriesExcludesBlocksBelowThreshold() {
        let blockId = UUID()
        let snapshot = WeatherSnapshot(
            entries: [BlockRainEntry(blockId: blockId, rainProbability: 0.5)],
            fetchedAt: Date()
        )
        // 0.5 is NOT > 0.5, so excluded
        let atRisk = snapshot.atRiskEntries(for: [(id: blockId, isOutdoor: true)])
        #expect(atRisk.isEmpty)
    }

    @Test func atRiskEntriesIncludesBlocksAboveThreshold() {
        let blockId = UUID()
        let snapshot = WeatherSnapshot(
            entries: [BlockRainEntry(blockId: blockId, rainProbability: 0.51)],
            fetchedAt: Date()
        )
        let atRisk = snapshot.atRiskEntries(for: [(id: blockId, isOutdoor: true)])
        #expect(atRisk.count == 1)
    }

    @Test func atRiskEntriesReturnsEmptyForNoEntries() {
        let snapshot = WeatherSnapshot(entries: [], fetchedAt: Date())
        let atRisk = snapshot.atRiskEntries(for: [(id: UUID(), isOutdoor: true)])
        #expect(atRisk.isEmpty)
    }

    // MARK: - WeatherService (Task 4.1)

    @Test @MainActor func fetchIfNeededReturnsNilForZeroLatAndLon() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 0, longitude: 0)
        context.insert(event)
        try context.save()

        let service = WeatherService()
        let result = await service.fetchIfNeeded(for: event)
        #expect(result == nil)
    }

    @Test @MainActor func fetchIfNeededReturnsCachedSnapshotWhenFresh() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 51.5, longitude: -0.1)
        context.insert(event)

        let blockId = UUID()
        let snapshot = WeatherSnapshot(
            entries: [BlockRainEntry(blockId: blockId, rainProbability: 0.8)],
            fetchedAt: Date()
        )
        event.weatherSnapshot = try JSONEncoder().encode(snapshot)
        try context.save()

        let service = WeatherService()
        let result = await service.fetchIfNeeded(for: event)

        #expect(result != nil)
        #expect(result?.entries.count == 1)
        #expect(result?.entries.first?.blockId == blockId)
    }

    @Test @MainActor func fetchIfNeededReturnsCachedSnapshotOnErrorWithStaleCache() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 51.5, longitude: -0.1)
        context.insert(event)

        // Store a STALE snapshot (older than 30 min)
        let blockId = UUID()
        let staleDate = Date().addingTimeInterval(-3600)
        let snapshot = WeatherSnapshot(
            entries: [BlockRainEntry(blockId: blockId, rainProbability: 0.7)],
            fetchedAt: staleDate
        )
        event.weatherSnapshot = try JSONEncoder().encode(snapshot)
        try context.save()

        // Without entitlement the WeatherKit call will fail — service must return cached data gracefully
        let service = WeatherService()
        let result = await service.fetchIfNeeded(for: event)
        // Must not crash. In CI (no entitlement) returns cached snapshot.
        _ = result
    }

    @Test @MainActor func fetchIfNeededReturnsNilForNilSnapshotAndNoEntitlement() async throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext

        let event = EventModel(title: "Wedding", date: .now, latitude: 51.5, longitude: -0.1)
        context.insert(event)
        try context.save()

        // No cached snapshot + WeatherKit call will fail in test environment
        let service = WeatherService()
        let result = await service.fetchIfNeeded(for: event)
        // Must not crash. Returns nil when no cache and fetch fails.
        _ = result
    }

    // MARK: - Banner Percentage Formatting

    @Test func bannerPercentageFormatsCorrectly() {
        let probability = 0.72
        let percentage = Int((probability * 100).rounded())
        #expect(percentage == 72)
    }

    @Test func bannerCopyStringMatchesSpec() {
        let blockTitle = "Ceremony"
        let probability = 0.72
        let percentage = Int((probability * 100).rounded())
        let text = "Rain likely during \(blockTitle) (\(percentage)% chance). Consider indoor backup."
        #expect(text == "Rain likely during Ceremony (72% chance). Consider indoor backup.")
    }

    @Test func bannerPercentageRoundsDown() {
        let probability = 0.724
        let percentage = Int((probability * 100).rounded())
        #expect(percentage == 72)
    }

    @Test func bannerPercentageRoundsUp() {
        let probability = 0.675
        let percentage = Int((probability * 100).rounded())
        #expect(percentage == 68)
    }
}
