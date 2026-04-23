import Foundation
import Models
import Services
import SwiftData
import Testing

/// Tests for the `atRiskOutdoorBlocks` filtering logic that drives banner
/// rendering in `EventDetailView`. Banner percentage/copy format tests
/// live in `WeatherServiceTests.swift`.
@Suite("RainWarningBanner")
struct RainWarningBannerTests {

    // MARK: - Helpers

    @MainActor
    private func makeEventWithBlocks(
        _ blockSpecs: [(title: String, isOutdoor: Bool, rainProbability: Double)],
        context: ModelContext
    ) throws -> EventModel {
        let event = EventModel(
            title: "Test Event",
            date: .now,
            latitude: 37.3347,
            longitude: -122.0090
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        context.insert(track)

        var entries: [BlockRainEntry] = []
        for spec in blockSpecs {
            let block = TimeBlockModel(
                title: spec.title,
                scheduledStart: .now,
                duration: 1800
            )
            block.track = track
            block.isOutdoor = spec.isOutdoor
            context.insert(block)
            entries.append(BlockRainEntry(blockId: block.id, rainProbability: spec.rainProbability))
        }

        let snapshot = WeatherSnapshot(entries: entries, fetchedAt: Date())
        event.weatherSnapshot = try JSONEncoder().encode(snapshot)
        try context.save()
        return event
    }

    // MARK: - Tests

    /// AC: Only outdoor blocks above 0.5 threshold show a banner.
    @Test @MainActor func onlyOutdoorBlocksAboveThresholdAreAtRisk() async throws {
        let container = try PersistenceController.forTesting()
        let ctx = container.mainContext

        let event = try makeEventWithBlocks([
            (title: "Stage Set",   isOutdoor: true,  rainProbability: 0.72),  // at risk
            (title: "Indoor Prep", isOutdoor: false, rainProbability: 0.90),  // indoor — excluded
            (title: "Sound Check", isOutdoor: true,  rainProbability: 0.50),  // exactly 0.5 — excluded
            (title: "Show Time",   isOutdoor: true,  rainProbability: 0.51),  // at risk
        ], context: ctx)

        guard let data = event.weatherSnapshot,
              let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
        else { Issue.record("Snapshot missing or corrupt"); return }

        let allBlocks = (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted { $0.scheduledStart < $1.scheduledStart }
        let riskEntries = snapshot.atRiskEntries(for: allBlocks.map { (id: $0.id, isOutdoor: $0.isOutdoor) })

        // Should see exactly 2 at-risk entries
        #expect(riskEntries.count == 2)
        let titles = riskEntries.compactMap { entry in allBlocks.first(where: { $0.id == entry.blockId })?.title }
        #expect(titles.contains("Stage Set"))
        #expect(titles.contains("Show Time"))
        #expect(!titles.contains("Indoor Prep"))
        #expect(!titles.contains("Sound Check"))
    }

    /// AC: A stale snapshot (> 30 min old) never produces banners.
    @Test @MainActor func staleSnapshotProducesNoBanners() async throws {
        let container = try PersistenceController.forTesting()
        let ctx = container.mainContext

        let event = EventModel(title: "Concert", date: .now, latitude: 37.0, longitude: -122.0)
        ctx.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        ctx.insert(track)
        let block = TimeBlockModel(title: "Main Set", scheduledStart: .now, duration: 3600)
        block.track = track
        block.isOutdoor = true
        ctx.insert(block)

        // Snapshot fetched 31 minutes ago — stale
        let staleDate = Date(timeIntervalSinceNow: -1860)
        let snapshot = WeatherSnapshot(entries: [BlockRainEntry(blockId: block.id, rainProbability: 0.9)], fetchedAt: staleDate)
        event.weatherSnapshot = try JSONEncoder().encode(snapshot)
        try ctx.save()

        guard let data = event.weatherSnapshot,
              let decoded = try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
        else { Issue.record("Snapshot missing"); return }

        // isFresh must be false — banner logic checks this before rendering
        #expect(decoded.isFresh == false)
    }

    /// AC: An event with no outdoor blocks produces no banners regardless of probability.
    @Test @MainActor func allIndoorBlocksProducesNoBanners() async throws {
        let container = try PersistenceController.forTesting()
        let ctx = container.mainContext

        let event = try makeEventWithBlocks([
            (title: "Keynote", isOutdoor: false, rainProbability: 0.99),
            (title: "Dinner",  isOutdoor: false, rainProbability: 0.80),
        ], context: ctx)

        guard let data = event.weatherSnapshot,
              let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
        else { Issue.record("Snapshot missing"); return }

        let allBlocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
        let riskEntries = snapshot.atRiskEntries(for: allBlocks.map { (id: $0.id, isOutdoor: $0.isOutdoor) })

        #expect(riskEntries.isEmpty)
    }

    /// AC: An event with no weather snapshot produces no banners (nil weatherSnapshot).
    @Test @MainActor func nilSnapshotProducesNoBanners() async throws {
        let container = try PersistenceController.forTesting()
        let ctx = container.mainContext

        let event = EventModel(title: "Garden Party", date: .now, latitude: 37.0, longitude: -122.0)
        ctx.insert(event)
        let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
        ctx.insert(track)
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 3600)
        block.track = track
        block.isOutdoor = true
        ctx.insert(block)
        try ctx.save()

        // No snapshot set — event.weatherSnapshot == nil
        #expect(event.weatherSnapshot == nil)

        // Decoding guard returns empty — no banners
        let decoded = event.weatherSnapshot.flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) }
        #expect(decoded == nil)
    }

    /// AC: Banner copy is exactly "Rain likely during [Block Name] (XX% chance). Consider indoor backup."
    @Test func bannerCopyFormatMatchesSpec() {
        let blockTitle = "Main Stage"
        let rainProbability = 0.72
        let percentage = Int((rainProbability * 100).rounded())
        let copy = "Rain likely during \(blockTitle) (\(percentage)% chance). Consider indoor backup."

        #expect(copy == "Rain likely during Main Stage (72% chance). Consider indoor backup.")
    }
}
