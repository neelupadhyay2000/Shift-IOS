//
//  shiftTimelineWidget.swift
//  shiftTimelineWidget
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import WidgetKit
import SwiftUI
import Models

// MARK: - Timeline Entry

struct ShiftWidgetEntry: TimelineEntry {
    let date: Date
    let activeBlockTitle: String
    let blockEndDate: Date
    let nextBlockTitle: String?
    let nextBlockStartTime: Date?
    let sunsetTime: Date?
    let eventName: String?
    let eventID: UUID?
    let isEventLive: Bool
    let nextEventDate: Date?
}

// MARK: - Timeline Provider

struct ShiftSmallProvider: TimelineProvider {

    func placeholder(in context: Context) -> ShiftWidgetEntry {
        ShiftWidgetEntry(
            date: .now,
            activeBlockTitle: "Cocktail Hour",
            blockEndDate: .now.addingTimeInterval(1935),
            nextBlockTitle: "First Dance",
            nextBlockStartTime: .now.addingTimeInterval(1935),
            sunsetTime: Calendar.current.date(bySettingHour: 20, minute: 14, second: 0, of: .now),
            eventName: "Wedding",
            eventID: nil,
            isEventLive: true,
            nextEventDate: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ShiftWidgetEntry) -> Void) {
        if context.isPreview {
            // Widget gallery — show realistic mock data
            completion(ShiftWidgetEntry(
                date: .now,
                activeBlockTitle: "Cocktail Hour",
                blockEndDate: .now.addingTimeInterval(1935),
                nextBlockTitle: "First Dance",
                nextBlockStartTime: .now.addingTimeInterval(1935),
                sunsetTime: Calendar.current.date(bySettingHour: 20, minute: 14, second: 0, of: .now),
                eventName: "Sarah & Tom's Wedding",
                eventID: UUID(),
                isEventLive: true,
                nextEventDate: nil
            ))
            return
        }

        let entry = makeEntry(date: .now)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftWidgetEntry>) -> Void) {
        let now = Date()
        var entries: [ShiftWidgetEntry] = []

        // Generate 60 entries, one per minute, for the next hour.
        for minuteOffset in 0..<60 {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: now)!
            entries.append(makeEntry(date: entryDate))
        }

        // Refresh again after the last entry.
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    // MARK: Helpers

    private func makeEntry(date: Date) -> ShiftWidgetEntry {
        guard let shared = WidgetDataStore.load(), shared.isEventLive else {
            let nextDate = WidgetDataStore.load()?.nextEventDate
            return ShiftWidgetEntry(
                date: date,
                activeBlockTitle: "",
                blockEndDate: date,
                nextBlockTitle: nil,
                nextBlockStartTime: nil,
                sunsetTime: nil,
                eventName: nil,
                eventID: nil,
                isEventLive: false,
                nextEventDate: nextDate
            )
        }

        return ShiftWidgetEntry(
            date: date,
            activeBlockTitle: shared.activeBlockTitle,
            blockEndDate: shared.blockEndDate,
            nextBlockTitle: shared.nextBlockTitle,
            nextBlockStartTime: shared.nextBlockStartTime,
            sunsetTime: shared.sunsetTime,
            eventName: shared.eventName,
            eventID: shared.eventID,
            isEventLive: true,
            nextEventDate: nil
        )
    }
}

// MARK: - Small Widget View

struct ShiftSmallWidgetView: View {
    var entry: ShiftWidgetEntry

    var body: some View {
        if entry.isEventLive {
            liveContent
        } else {
            noEventContent
        }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Block title
            Text(entry.activeBlockTitle)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)

            Spacer()

            // Live countdown timer — the system renders this in real time
            // without requiring additional app wakeups.
            Label {
                Text(entry.blockEndDate, style: .timer)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            }

            Text("remaining")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noEventContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("No Active Event")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let nextDate = entry.nextEventDate {
                Text("Next event: \(nextDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No upcoming events")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget Configuration

struct ShiftSmallWidget: Widget {
    let kind: String = "ShiftSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShiftSmallProvider()) { entry in
            ShiftSmallWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.isEventLive
                    ? URL(string: "shift://live/\(entry.eventID?.uuidString ?? "")")
                    : nil
                )
        }
        .configurationDisplayName("SHIFT Timeline")
        .description("Current block and countdown timer.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Previews

#Preview("Small — Live", as: .systemSmall) {
    ShiftSmallWidget()
} timeline: {
    ShiftWidgetEntry(
        date: .now,
        activeBlockTitle: "Ceremony",
        blockEndDate: .now.addingTimeInterval(1800),
        nextBlockTitle: nil,
        nextBlockStartTime: nil,
        sunsetTime: nil,
        eventName: nil,
        eventID: UUID(),
        isEventLive: true,
        nextEventDate: nil
    )
}

#Preview("Small — No Event (with upcoming)", as: .systemSmall) {
    ShiftSmallWidget()
} timeline: {
    ShiftWidgetEntry(
        date: .now,
        activeBlockTitle: "",
        blockEndDate: .now,
        nextBlockTitle: nil,
        nextBlockStartTime: nil,
        sunsetTime: nil,
        eventName: nil,
        eventID: nil,
        isEventLive: false,
        nextEventDate: Calendar.current.date(byAdding: .day, value: 3, to: .now)
    )
}

#Preview("Small — No Event (none)", as: .systemSmall) {
    ShiftSmallWidget()
} timeline: {
    ShiftWidgetEntry(
        date: .now,
        activeBlockTitle: "",
        blockEndDate: .now,
        nextBlockTitle: nil,
        nextBlockStartTime: nil,
        sunsetTime: nil,
        eventName: nil,
        eventID: nil,
        isEventLive: false,
        nextEventDate: nil
    )
}

// MARK: - Medium Widget View

struct ShiftMediumWidgetView: View {
    var entry: ShiftWidgetEntry

    var body: some View {
        if entry.isEventLive {
            liveContent
        } else {
            noEventContent
        }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1 — Current block + countdown
            HStack {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(entry.activeBlockTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(entry.blockEndDate, style: .timer)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.orange)
            }

            Divider()

            // Row 2 — Next block + start time
            HStack {
                Image(systemName: "forward.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let next = entry.nextBlockTitle {
                    Text(next)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer()
                    if let startTime = entry.nextBlockStartTime {
                        Text("Starts at \(startTime.formatted(.dateTime.hour().minute()))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Last block of the day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            Divider()

            // Row 3 — Sunset countdown
            HStack {
                Image(systemName: "sunset.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text("Sunset")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                if let sunset = entry.sunsetTime {
                    Text(sunset, style: .timer)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.yellow)
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noEventContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("No Active Event")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let nextDate = entry.nextEventDate {
                Text("Next event: \(nextDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No upcoming events")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Medium Widget Configuration

struct ShiftMediumWidget: Widget {
    let kind: String = "ShiftMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShiftSmallProvider()) { entry in
            ShiftMediumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.isEventLive
                    ? URL(string: "shift://live/\(entry.eventID?.uuidString ?? "")")
                    : nil
                )
        }
        .configurationDisplayName("SHIFT Timeline")
        .description("Current block, next block, and sunset countdown.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Medium Previews

#Preview("Medium — Live", as: .systemMedium) {
    ShiftMediumWidget()
} timeline: {
    ShiftWidgetEntry(
        date: .now,
        activeBlockTitle: "Ceremony",
        blockEndDate: .now.addingTimeInterval(1800),
        nextBlockTitle: "Reception",
        nextBlockStartTime: .now.addingTimeInterval(3600),
        sunsetTime: .now.addingTimeInterval(7200),
        eventName: "Wedding",
        eventID: UUID(),
        isEventLive: true,
        nextEventDate: nil
    )
}

#Preview("Medium — No Event (with upcoming)", as: .systemMedium) {
    ShiftMediumWidget()
} timeline: {
    ShiftWidgetEntry(
        date: .now,
        activeBlockTitle: "",
        blockEndDate: .now,
        nextBlockTitle: nil,
        nextBlockStartTime: nil,
        sunsetTime: nil,
        eventName: nil,
        eventID: nil,
        isEventLive: false,
        nextEventDate: Calendar.current.date(byAdding: .day, value: 3, to: .now)
    )
}

#Preview("Medium — No Event (none)", as: .systemMedium) {
    ShiftMediumWidget()
} timeline: {
    ShiftWidgetEntry(
        date: .now,
        activeBlockTitle: "",
        blockEndDate: .now,
        nextBlockTitle: nil,
        nextBlockStartTime: nil,
        sunsetTime: nil,
        eventName: nil,
        eventID: nil,
        isEventLive: false,
        nextEventDate: nil
    )
}
