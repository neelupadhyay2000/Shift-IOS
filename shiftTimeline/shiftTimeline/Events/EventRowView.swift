import SwiftUI
import Models

/// A single row in the event roster list — Direction A ("calm pro-tool").
///
/// Luma-style anatomy: a leading date tile (the "when" first), a strong title,
/// and a quiet uppercase status line. Live events swap the date tile for a
/// pulsing emerald beacon. No decorative colour — the status hue is the only
/// accent in the row.
struct EventRowView: View {

    let title: String
    let date: Date
    let status: EventStatus
    var isShared: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            dateTile

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Circle()
                        .fill(status.tintColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(status.label)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .kerning(0.8)
                        .foregroundStyle(status.tintColor)
                    Text(verbatim: "·")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Text(EventCountdown.label(for: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isShared {
                        Text(verbatim: "·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(String(localized: "Shared"))
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Date tile

    /// Compact calendar tile: big tabular day number over a month micro-label.
    /// A live event replaces it with an emerald "on air" beacon.
    @ViewBuilder
    private var dateTile: some View {
        Group {
            if status == .live {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ShiftPalette.live)
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                VStack(spacing: 1) {
                    Text(date, format: .dateTime.day())
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text(date, format: .dateTime.month(.abbreviated))
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .kerning(0.5)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 48, height: 48)
        .background(
            colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    status == .live
                        ? ShiftPalette.live.opacity(0.45)
                        : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                    lineWidth: 1
                )
        )
        .accessibilityHidden(true)
    }

    private var accessibilityDescription: String {
        let dateStr = date.formatted(.dateTime.month(.wide).day().year())
        var parts = ["\(title), \(dateStr), \(status.label)"]
        if isShared { parts.append(String(localized: "Shared")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - EventStatus helpers

extension EventStatus {

    var label: String {
        switch self {
        case .planning:  String(localized: "Planning")
        case .live:      String(localized: "Live")
        case .completed: String(localized: "Completed")
        }
    }

    var tintColor: Color {
        switch self {
        case .planning:  ShiftPalette.accent
        case .live:      ShiftPalette.live
        case .completed: ShiftPalette.neutral
        }
    }
}
