import WidgetKit
import SwiftUI
import Models

// MARK: - Timeline Entry

struct NextBlockEntry: TimelineEntry {
    let date: Date
    let eventID: UUID?
    let blockTitle: String?
    let minutesUntilStart: Int?
    let isLive: Bool
}

// MARK: - Timeline Provider

struct NextBlockProvider: TimelineProvider {

    func placeholder(in context: Context) -> NextBlockEntry {
        NextBlockEntry(date: .now, eventID: nil, blockTitle: "Cocktail Hour", minutesUntilStart: 12, isLive: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextBlockEntry) -> Void) {
        if let stored = WatchContextStore.load(), stored.isLive {
            completion(makeEntry(from: stored, at: .now))
        } else {
            completion(NextBlockEntry(date: .now, eventID: nil, blockTitle: nil, minutesUntilStart: nil, isLive: false))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextBlockEntry>) -> Void) {
        guard let stored = WatchContextStore.load(), stored.isLive else {
            // No live event — single fallback entry, retry in 15 minutes.
            let entry = NextBlockEntry(date: .now, eventID: nil, blockTitle: nil, minutesUntilStart: nil, isLive: false)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
            return
        }

        let now = Date.now
        var entries: [NextBlockEntry] = []

        // Generate entries every 5 minutes for the next 2 hours (24 entries).
        // Each entry recalculates the countdown from its own date so the
        // complication shows the correct "Xm" as time progresses.
        for minuteOffset in stride(from: 0, through: 115, by: 5) {
            let entryDate = now.addingTimeInterval(TimeInterval(minuteOffset * 60))
            entries.append(makeEntry(from: stored, at: entryDate))
        }

        // Request a fresh timeline after the 2-hour window.
        let refreshDate = now.addingTimeInterval(2 * 60 * 60)
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }

    /// Builds an entry from the locally cached WCSession context.
    /// No network or API calls — data comes exclusively from the synced store.
    private func makeEntry(from stored: WatchContext, at date: Date) -> NextBlockEntry {
        guard let nextTitle = stored.nextBlockTitle,
              let nextStart = stored.nextBlockStartTime else {
            // Live but no next block — last block of the day.
            return NextBlockEntry(date: date, eventID: stored.eventID, blockTitle: nil, minutesUntilStart: nil, isLive: true)
        }

        let minutes = max(0, Int(nextStart.timeIntervalSince(date) / 60))
        return NextBlockEntry(date: date, eventID: stored.eventID, blockTitle: nextTitle, minutesUntilStart: minutes, isLive: true)
    }
}

// MARK: - Complication Views

struct NextBlockComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NextBlockEntry

    var body: some View {
        switch family {
        case .accessoryCorner:
            cornerView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            inlineView
        }
    }

    // MARK: - Inline

    private var inlineView: some View {
        ViewThatFits {
            if let title = entry.blockTitle, let minutes = entry.minutesUntilStart {
                Text("Next: \(title) in \(minutes)m")
            } else if entry.isLive {
                Text(String(localized: "Last block"))
            } else {
                Text(String(localized: "No active event"))
            }
        }
    }

    // MARK: - Corner

    private var cornerView: some View {
        Image(systemName: "calendar.badge.clock")
            .font(.title3)
            .widgetLabel {
                if let title = entry.blockTitle, let minutes = entry.minutesUntilStart {
                    Text("\(title) in \(minutes)m")
                } else if entry.isLive {
                    Text(String(localized: "Last block"))
                } else {
                    Text(String(localized: "No event"))
                }
            }
    }

    // MARK: - Rectangular (modular)

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title = entry.blockTitle, let minutes = entry.minutesUntilStart {
                Text(String(localized: "Up Next"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text("in \(minutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if entry.isLive {
                Text(String(localized: "Up Next"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Last block of the day"))
                    .font(.caption)
            } else {
                Text(String(localized: "SHIFT"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(localized: "No active event"))
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget Definition

struct NextBlockComplication: Widget {
    let kind = "com.neelsoftwaresolutions.shiftTimeline.nextBlock"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextBlockProvider()) { entry in
            NextBlockComplicationView(entry: entry)
                .privacySensitive(false)
                .widgetURL(entry.eventID.map { URL(string: "shift://live/\($0.uuidString)")! })
        }
        .configurationDisplayName(String(localized: "Next Block"))
        .description(String(localized: "Shows the next block on your timeline."))
        .supportedFamilies([
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - Previews

#Preview(as: .accessoryInline) {
    NextBlockComplication()
} timeline: {
    NextBlockEntry(date: .now, eventID: nil, blockTitle: "Cocktail Hour", minutesUntilStart: 12, isLive: true)
    NextBlockEntry(date: .now, eventID: nil, blockTitle: nil, minutesUntilStart: nil, isLive: false)
}

#Preview(as: .accessoryRectangular) {
    NextBlockComplication()
} timeline: {
    NextBlockEntry(date: .now, eventID: nil, blockTitle: "Cocktail Hour", minutesUntilStart: 12, isLive: true)
    NextBlockEntry(date: .now, eventID: nil, blockTitle: nil, minutesUntilStart: nil, isLive: true)
    NextBlockEntry(date: .now, eventID: nil, blockTitle: nil, minutesUntilStart: nil, isLive: false)
}

#Preview(as: .accessoryCorner) {
    NextBlockComplication()
} timeline: {
    NextBlockEntry(date: .now, eventID: nil, blockTitle: "Cocktail Hour", minutesUntilStart: 12, isLive: true)
    NextBlockEntry(date: .now, eventID: nil, blockTitle: nil, minutesUntilStart: nil, isLive: false)
}
