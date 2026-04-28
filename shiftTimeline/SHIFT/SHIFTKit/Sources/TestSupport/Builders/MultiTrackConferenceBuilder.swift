import Foundation
import Models
import SwiftData

struct MultiTrackConferenceBuilder: FixtureBuilding {
    @MainActor
    func build(into context: ModelContext, clock: TestClock) throws {
        let event = EventModel(
            title: "Grand Gala Evening",
            date: clock.now,
            latitude: 40.7128,
            longitude: -74.0060
        )
        context.insert(event)

        let mainTrack      = TimelineTrack(name: "Main",      sortOrder: 0, isDefault: true, event: event)
        let ceremonyTrack  = TimelineTrack(name: "Ceremony",  sortOrder: 1, event: event)
        let receptionTrack = TimelineTrack(name: "Reception", sortOrder: 2, event: event)
        context.insert(mainTrack)
        context.insert(ceremonyTrack)
        context.insert(receptionTrack)

        let mainSpecs: [(String, TimeInterval, TimeInterval)] = [
            ("Guest Arrival",  0,     1800),
            ("Cocktails",      1800,  3600),
            ("After-Party",    18000, 3600),
        ]
        for spec in mainSpecs {
            let block = TimeBlockModel(title: spec.0, scheduledStart: clock.now.addingTimeInterval(spec.1), duration: spec.2)
            block.track = mainTrack
            context.insert(block)
        }

        let ceremonySpecs: [(String, TimeInterval, TimeInterval)] = [
            ("Processional",    5400, 900),
            ("Exchange of Vows", 6300, 1800),
        ]
        for spec in ceremonySpecs {
            let block = TimeBlockModel(title: spec.0, scheduledStart: clock.now.addingTimeInterval(spec.1), duration: spec.2)
            block.track = ceremonyTrack
            context.insert(block)
        }

        let receptionSpecs: [(String, TimeInterval, TimeInterval)] = [
            ("Dinner Service", 9000,  5400),
            ("First Dance",    14400, 900),
        ]
        for spec in receptionSpecs {
            let block = TimeBlockModel(title: spec.0, scheduledStart: clock.now.addingTimeInterval(spec.1), duration: spec.2)
            block.track = receptionTrack
            context.insert(block)
        }
    }
}
