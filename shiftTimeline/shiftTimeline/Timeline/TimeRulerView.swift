import SwiftUI
import Models

/// Configuration for the time ruler's visible range and scale.
struct TimeRulerLayout {
    let rulerStart: Date
    let rulerEnd: Date
    let pointsPerMinute: CGFloat

    /// Total height of the ruler in points.
    var totalHeight: CGFloat {
        let minutes = rulerEnd.timeIntervalSince(rulerStart) / 60
        return CGFloat(minutes) * pointsPerMinute
    }

    /// The Y offset for a given date relative to the ruler start.
    func yOffset(for date: Date) -> CGFloat {
        let minutes = date.timeIntervalSince(rulerStart) / 60
        return CGFloat(minutes) * pointsPerMinute
    }

    /// The height for a given duration.
    func height(for duration: TimeInterval) -> CGFloat {
        CGFloat(duration / 60) * pointsPerMinute
    }

    /// Hour dates from rulerStart to rulerEnd (inclusive of both boundary hours).
    var hourMarkers: [Date] {
        let calendar = Calendar.current
        guard let firstHour = calendar.nextDate(
            after: rulerStart.addingTimeInterval(-1),
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return [] }

        var markers: [Date] = []
        var current = firstHour
        while current <= rulerEnd {
            markers.append(current)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: current) else { break }
            current = next
        }
        return markers
    }

    /// Creates a layout that adapts to the event's actual time range.
    ///
    /// Rounds start down and end up to the nearest hour, with padding.
    static func adaptive(
        blocks: [some TimeRulerBlock],
        pointsPerMinute: CGFloat = 1.5
    ) -> TimeRulerLayout {
        let calendar = Calendar.current

        guard let earliest = blocks.min(by: { $0.blockStart < $1.blockStart }),
              let latest = blocks.max(by: { $0.blockEnd < $1.blockEnd }) else {
            let now = Date.now
            return TimeRulerLayout(
                rulerStart: calendar.startOfHour(for: now),
                rulerEnd: calendar.startOfHour(for: now.addingTimeInterval(3600)),
                pointsPerMinute: pointsPerMinute
            )
        }

        let startHour = calendar.startOfHour(for: earliest.blockStart)
        let endDate = latest.blockEnd
        let endHour = calendar.startOfHour(for: endDate)
        let rulerEnd = endHour < endDate
            ? endHour.addingTimeInterval(3600)
            : endHour

        return TimeRulerLayout(
            rulerStart: startHour,
            rulerEnd: rulerEnd,
            pointsPerMinute: pointsPerMinute
        )
    }
}

/// Protocol for blocks that can be positioned on the ruler.
protocol TimeRulerBlock {
    var blockStart: Date { get }
    var blockEnd: Date { get }
}

// MARK: - Calendar helper

private extension Calendar {
    func startOfHour(for date: Date) -> Date {
        let comps = dateComponents([.year, .month, .day, .hour], from: date)
        return self.date(from: comps) ?? date
    }
}

// MARK: - TimeBlockModel conformance

extension TimeBlockModel: TimeRulerBlock {
    public var blockStart: Date { scheduledStart }
    public var blockEnd: Date { scheduledStart.addingTimeInterval(duration) }
}

// MARK: - TimeRulerView

/// Draws vertical hour markers along the left edge.
struct TimeRulerView: View {
    let layout: TimeRulerLayout

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.hourMarkers, id: \.self) { hour in
                HStack(spacing: 4) {
                    Text(Self.hourFormatter.string(from: hour))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 0.5)
                }
                .offset(y: layout.yOffset(for: hour) - 6)
            }
        }
        .frame(height: layout.totalHeight)
    }
}
