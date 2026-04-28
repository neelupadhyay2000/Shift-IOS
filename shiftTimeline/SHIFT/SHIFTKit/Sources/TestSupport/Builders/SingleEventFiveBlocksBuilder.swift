import Foundation
import Models
import SwiftData

struct SingleEventFiveBlocksBuilder: FixtureBuilding {
    @MainActor
    func build(into context: ModelContext, clock: TestClock) throws {
        let event = EventModel(
            title: "Morning Workshop",
            date: clock.now,
            latitude: 37.7749,
            longitude: -122.4194
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let blockTitles = ["Welcome & Intro", "Session 1", "Break", "Session 2", "Wrap-Up"]
        for (index, title) in blockTitles.enumerated() {
            let start = clock.now.addingTimeInterval(Double(index) * 1800)
            let block = TimeBlockModel(title: title, scheduledStart: start, duration: 1800)
            block.track = track
            context.insert(block)
        }
    }
}
