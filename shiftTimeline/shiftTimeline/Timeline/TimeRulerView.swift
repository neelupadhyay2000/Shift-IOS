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

    /// Hour and quarter-hour dates from rulerStart to rulerEnd at 15-minute intervals.
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
            guard let next = calendar.date(byAdding: .minute, value: 15, to: current) else { break }
            current = next
        }
        return markers
    }

    /// Creates a layout that adapts to the event's actual time range.
    ///
    /// Rounds start down and end up to the nearest hour, with padding.
    static func adaptive(
        blocks: [some TimeRulerBlock],
        pointsPerMinute: CGFloat = 4.0
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

/// Draws vertical hour markers along the left edge with a continuous
/// vertical line connecting hour ticks for a polished, modern look.
struct TimeRulerView: View {
    let layout: TimeRulerLayout

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f
    }()

    private static let halfHourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Continuous vertical guide line — subtle gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.15), Color.secondary.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1.5)
                .frame(height: layout.totalHeight)
                .offset(x: 55.5)

            ForEach(layout.hourMarkers, id: \.self) { marker in
                let y = layout.yOffset(for: marker)
                let minuteComponent = Calendar.current.component(.minute, from: marker)
                let isFullHour = minuteComponent == 0
                let isHalfHour = minuteComponent == 30
                let showLabel = isFullHour || isHalfHour

                HStack(spacing: 6) {
                    Group {
                        if showLabel {
                            Text(isFullHour
                                 ? Self.hourFormatter.string(from: marker)
                                 : Self.halfHourFormatter.string(from: marker))
                                .font(.caption2)
                                .fontWeight(isFullHour ? .bold : .regular)
                                .foregroundStyle(isFullHour ? .secondary : .tertiary)
                                .monospacedDigit()
                        } else {
                            // Quarter-hour markers — no label, just the tick
                            Color.clear
                        }
                    }
                    .frame(width: 42, alignment: .trailing)

                    // Tick mark — larger for full hours, smaller for halves, smallest for quarters
                    let outer: CGFloat = isFullHour ? 7 : (isHalfHour ? 5 : 3)
                    let halo: CGFloat = isFullHour ? 13 : (isHalfHour ? 9 : 6)
                    let opacity: Double = isFullHour ? 0.4 : (isHalfHour ? 0.2 : 0.12)
                    let haloOpacity: Double = isFullHour ? 0.15 : (isHalfHour ? 0.08 : 0.05)

                    Circle()
                        .fill(Color.accentColor.opacity(opacity))
                        .frame(width: outer, height: outer)
                        .overlay(
                            Circle()
                                .fill(Color.accentColor.opacity(haloOpacity))
                                .frame(width: halo, height: halo)
                        )
                }
                .offset(y: y - 3)
            }
        }
        .frame(width: 64, height: layout.totalHeight, alignment: .topLeading)
    }
}
