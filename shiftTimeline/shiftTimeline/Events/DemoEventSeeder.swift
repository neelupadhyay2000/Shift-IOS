import Foundation
import Models
import Services

/// Seeds a ready-to-run demo event from a bundled starter template so a brand-new
/// user can experience Go Live and the Ripple Engine without building a timeline
/// first (the empty roster's "Try a Demo Event" action).
///
/// Blocks are anchored at `now`, so the first block is immediately active with a
/// real countdown the moment the user goes live — and "+10 min" visibly ripples
/// the rest of the day.
@MainActor
enum DemoEventSeeder {

    /// Used when the bundled templates can't be loaded — the demo must never
    /// fail silently on the one tap most likely to convert a new user.
    nonisolated static let fallbackTemplate = Template(
        name: String(localized: "Sample Event"),
        description: String(localized: "A short sample timeline."),
        category: .social,
        blocks: [
            TemplateBlock(
                title: String(localized: "Guest Arrival"),
                relativeStartOffset: 0, duration: 1800,
                colorTag: "#34C759", icon: "person.2.fill"
            ),
            TemplateBlock(
                title: String(localized: "Welcome Toast"),
                relativeStartOffset: 1800, duration: 900,
                colorTag: "#FF9500", icon: "wineglass.fill"
            ),
            TemplateBlock(
                title: String(localized: "Dinner Service"),
                relativeStartOffset: 2700, duration: 3600, isPinned: true,
                colorTag: "#FF3B30", icon: "fork.knife"
            ),
            TemplateBlock(
                title: String(localized: "First Dance"),
                relativeStartOffset: 6300, duration: 1200,
                colorTag: "#AF52DE", icon: "music.note"
            ),
        ]
    )

    /// Creates the demo event and returns its ID for navigation, or `nil` when
    /// persistence failed. Routes every write through the injected repositories
    /// so the demo behaves exactly like a real event (sync included).
    static func seed(
        eventRepo: any EventRepositing,
        trackRepo: any TrackRepositing,
        blockRepo: any BlockRepositing,
        now: Date = .now
    ) async -> UUID? {
        let template = pickTemplate()

        let event = EventModel(
            title: String(localized: "Demo: \(template.name)"),
            date: now,
            latitude: 0,
            longitude: 0
        )
        do {
            try await eventRepo.insert(event)

            let mainTrack = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
            try await trackRepo.insert(mainTrack, into: event)

            for templateBlock in template.blocks {
                let block = TimeBlockModel(
                    title: templateBlock.title,
                    scheduledStart: now.addingTimeInterval(templateBlock.relativeStartOffset),
                    duration: templateBlock.duration,
                    isPinned: templateBlock.isPinned,
                    colorTag: templateBlock.colorTag,
                    icon: templateBlock.icon
                )
                try await blockRepo.insert(block, into: mainTrack)
            }

            try await eventRepo.save()
        } catch {
            return nil
        }

        AnalyticsService.send(.demoEventCreated, parameters: ["templateName": template.name])
        return event.id
    }

    /// Prefers a wedding template (the marquee use case), falls back to the
    /// largest bundled template, then to the built-in sample.
    private static func pickTemplate() -> Template {
        let bundled = (try? TemplateLoader().loadAll()) ?? []
        if let wedding = bundled.first(where: { $0.category == .wedding && !$0.blocks.isEmpty }) {
            return wedding
        }
        if let biggest = bundled.max(by: { $0.blocks.count < $1.blocks.count }), !biggest.blocks.isEmpty {
            return biggest
        }
        return fallbackTemplate
    }
}
