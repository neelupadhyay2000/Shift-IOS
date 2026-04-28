import Foundation
import Models
import SwiftData

struct LiveEventInProgressBuilder: FixtureBuilding {
    let blockIndex: Int

    @MainActor
    func build(into context: ModelContext, clock: TestClock) throws {
        let event = EventModel(
            title: "Live Wedding Day",
            date: clock.now,
            latitude: 37.7749,
            longitude: -122.4194,
            status: .live
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let blockTitles = ["Getting Ready", "First Look", "Ceremony", "Cocktail Hour", "Reception"]
        for (index, title) in blockTitles.enumerated() {
            let status: BlockStatus
            if index < blockIndex {
                status = .completed
            } else if index == blockIndex {
                status = .active
            } else {
                status = .upcoming
            }
            let block = TimeBlockModel(
                title: title,
                scheduledStart: clock.now.addingTimeInterval(Double(index) * 1800),
                duration: 1800,
                status: status
            )
            block.track = track
            context.insert(block)
        }
    }
}
