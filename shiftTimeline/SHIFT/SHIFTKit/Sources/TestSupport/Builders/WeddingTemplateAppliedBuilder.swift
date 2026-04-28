import Foundation
import Models
import SwiftData

/// Reproduces the 15-block "Traditional Wedding" timeline from `classic-wedding.json`.
/// Block offsets and durations are sourced verbatim from the JSON resource.
struct WeddingTemplateAppliedBuilder: FixtureBuilding {
    @MainActor
    func build(into context: ModelContext, clock: TestClock) throws {
        let event = EventModel(
            title: "Smith–Jones Wedding",
            date: clock.now,
            latitude: 34.0195,
            longitude: -118.4912
        )
        context.insert(event)

        let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
        context.insert(track)

        let blockSpecs: [(title: String, offset: TimeInterval, duration: TimeInterval, isPinned: Bool, colorTag: String, icon: String)] = [
            ("Bridal Suite Prep",              0,     5400, false, "#FF2D55", "star.fill"),
            ("Groomsmen Prep",              1800,     3600, false, "#007AFF", "person.2.fill"),
            ("First Look",                  5400,     1800, false, "#AF52DE", "camera.fill"),
            ("Wedding Party Portraits",     7200,     2700, false, "#AF52DE", "camera.fill"),
            ("Family Portraits",            9900,     1800, false, "#AF52DE", "camera.fill"),
            ("Guest Seating",             11700,     1800, false, "#8E8E93", "person.2.fill"),
            ("Ceremony",                  13500,     2700,  true, "#FF3B30", "heart.fill"),
            ("Cocktail Hour",             16200,     3600, false, "#FF9500", "fork.knife"),
            ("Couple Portraits (Golden Hour)", 18000, 1800, false, "#FFCC00", "sun.max.fill"),
            ("Grand Entrance",            19800,      900, false, "#34C759", "music.note"),
            ("First Dance",               20700,      900, false, "#FFCC00", "music.note"),
            ("Dinner Service",            21600,     3600, false, "#34C759", "fork.knife"),
            ("Toasts & Speeches",         25200,     1800, false, "#007AFF", "mic.fill"),
            ("Cake Cutting & Open Dancing", 27000,    900, false, "#FF2D55", "gift.fill"),
            ("Sparkler Send-Off",         27900,      900, false, "#FFCC00", "car.fill"),
        ]

        for spec in blockSpecs {
            let block = TimeBlockModel(
                title: spec.title,
                scheduledStart: clock.now.addingTimeInterval(spec.offset),
                duration: spec.duration,
                isPinned: spec.isPinned,
                colorTag: spec.colorTag,
                icon: spec.icon
            )
            block.track = track
            context.insert(block)
        }
    }
}
