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
    let eventID: UUID?
    let isEventLive: Bool
}

// MARK: - Timeline Provider

struct ShiftSmallProvider: TimelineProvider {

    func placeholder(in context: Context) -> ShiftWidgetEntry {
        ShiftWidgetEntry(
            date: .now,
            activeBlockTitle: "Ceremony",
            blockEndDate: .now.addingTimeInterval(1800),
            eventID: nil,
            isEventLive: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ShiftWidgetEntry) -> Void) {
        if context.isPreview {
            // Widget gallery — show realistic mock data
            completion(ShiftWidgetEntry(
                date: .now,
                activeBlockTitle: "First Dance",
                blockEndDate: .now.addingTimeInterval(2400),
                eventID: UUID(),
                isEventLive: true
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
            return ShiftWidgetEntry(
                date: date,
                activeBlockTitle: "",
                blockEndDate: date,
                eventID: nil,
                isEventLive: false
            )
        }

        return ShiftWidgetEntry(
            date: date,
            activeBlockTitle: shared.activeBlockTitle,
            blockEndDate: shared.blockEndDate,
            eventID: shared.eventID,
            isEventLive: true
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
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No Active Event")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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

#Preview("Live Event", as: .systemSmall) {
    ShiftSmallWidget()
} timeline: {
    ShiftWidgetEntry(
        date: .now,
        activeBlockTitle: "Ceremony",
        blockEndDate: .now.addingTimeInterval(1800),
        eventID: UUID(),
        isEventLive: true
    )
}

#Preview("No Event", as: .systemSmall) {
    ShiftSmallWidget()
} timeline: {
    ShiftWidgetEntry(
        date: .now,
        activeBlockTitle: "",
        blockEndDate: .now,
        eventID: nil,
        isEventLive: false
    )
}
