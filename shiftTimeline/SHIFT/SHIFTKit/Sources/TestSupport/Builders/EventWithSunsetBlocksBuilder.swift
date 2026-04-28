import Foundation
import Models
import SwiftData

struct EventWithSunsetBlocksBuilder: FixtureBuilding {
    @MainActor
    func build(into context: ModelContext, clock: TestClock) throws {
        // Reference noon + 7.5 h = 7:30 PM (golden hour), + 8 h = 8:00 PM (sunset)
        let goldenHourStart = clock.now.addingTimeInterval(7.5 * 3600)
        let sunsetTime      = clock.now.addingTimeInterval(8.0 * 3600)

        let event = EventModel(
            title: "Sunset Rooftop Wedding",
            date: clock.now,
            latitude: 34.0522,
            longitude: -118.2437,
            sunsetTime: sunsetTime,
            goldenHourStart: goldenHourStart
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let blockSpecs: [(String, TimeInterval, TimeInterval)] = [
            ("Rooftop Cocktails",      0,          3600),
            ("Golden Hour Portraits",  7.5 * 3600, 1800),
            ("Sunset Ceremony",        8.0 * 3600, 2700),
        ]
        for spec in blockSpecs {
            let block = TimeBlockModel(
                title: spec.0,
                scheduledStart: clock.now.addingTimeInterval(spec.1),
                duration: spec.2
            )
            block.track = track
            context.insert(block)
        }
    }
}
