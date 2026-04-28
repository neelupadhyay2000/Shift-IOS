import Foundation
import Models
import SwiftData

struct EventWithVendorsBuilder: FixtureBuilding {
    let count: Int

    @MainActor
    func build(into context: ModelContext, clock: TestClock) throws {
        let event = EventModel(
            title: "Vendor Showcase",
            date: clock.now,
            latitude: 37.7749,
            longitude: -122.4194
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let block = TimeBlockModel(title: "Main Show", scheduledStart: clock.now, duration: 3600)
        block.track = track
        context.insert(block)

        let roles = VendorRole.allCases
        for index in 0..<count {
            let vendor = VendorModel(
                name: "Vendor \(index + 1)",
                role: roles[index % roles.count],
                email: "vendor\(index + 1)@example.com"
            )
            vendor.event = event
            context.insert(vendor)
        }
    }
}
