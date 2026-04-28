import Foundation
import Models
import SwiftData

struct EventWithRainForecastedBlockBuilder: FixtureBuilding {
    @MainActor
    func build(into context: ModelContext, clock: TestClock) throws {
        let event = EventModel(
            title: "Outdoor Garden Party",
            date: clock.now,
            latitude: 37.8716,
            longitude: -122.2727
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Garden Ceremony", scheduledStart: clock.now, duration: 3600)
        block.isOutdoor = true
        block.track = track
        context.insert(block)

        // fetchedAt uses clock.now so the snapshot timestamp is deterministic.
        // Unit tests should verify snapshot structure, not isFresh (which depends on real wall time).
        let entry = BlockRainEntry(blockId: block.id, rainProbability: 0.8)
        let snapshot = WeatherSnapshot(entries: [entry], fetchedAt: clock.now)
        event.weatherSnapshot = try JSONEncoder().encode(snapshot)
    }
}
