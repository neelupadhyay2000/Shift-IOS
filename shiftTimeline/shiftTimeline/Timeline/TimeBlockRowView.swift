import SwiftUI
import Models

/// A single row in the timeline builder list.
/// Displays color accent, icon, title, start time, duration, and a Fluid/Pinned indicator.
///
/// When `isCompact` is true, renders a slim single-line variant suitable for short
/// blocks (e.g. transit blocks) that don't have enough vertical real estate for the
/// full layout. The compact mode fits cleanly in ~36pt of height.
struct TimeBlockRowView: View {

    let title: String
    let scheduledStart: Date
    let duration: TimeInterval
    let isPinned: Bool
    let colorTag: String
    let icon: String
    var isCompact: Bool = false

    private var accentColor: Color {
        isPinned ? Color(.systemRed) : Color(hex: colorTag)
    }

    var body: some View {
        if isCompact {
            compactBody
        } else {
            fullBody
        }
    }

    // MARK: - Full layout

    private var fullBody: some View {
        HStack(spacing: 0) {
            // Left accent bar — gradient strip
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 2, topTrailingRadius: 2)
                .fill(accentColor.gradient)
                .frame(width: 5)
                .padding(.vertical, 4)

            HStack(spacing: 12) {
                // Icon circle — larger with gradient fill
                ZStack {
                    RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous)
                        .fill(Color(hex: colorTag).gradient.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: colorTag))
                        .symbolEffect(.bounce, value: isPinned)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(scheduledStart, format: .dateTime.hour().minute())
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text(formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                // Status badge
                HStack(spacing: 4) {
                    Image(systemName: isPinned ? "pin.fill" : "arrow.up.arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(isPinned ? String(localized: "Pinned") : String(localized: "Fluid"))
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(accentColor)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Compact layout

    /// Slim single-line row for short blocks. ~32pt tall.
    private var compactBody: some View {
        HStack(spacing: 0) {
            // Thinner accent bar
            UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 2, topTrailingRadius: 2)
                .fill(accentColor.gradient)
                .frame(width: 4)
                .padding(.vertical, 3)

            HStack(spacing: 8) {
                // Smaller icon, no background tile
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: colorTag))
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Inline time · duration
                Text(formattedDuration)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }

    /// Spoken label: "[Title], [N minutes/hours], [Fluid/Pinned], starts at [HH:MM]"
    private var accessibilityDescription: String {
        let totalMinutes = Int(duration) / 60
        let durationStr: String
        if totalMinutes < 60 {
            durationStr = "\(totalMinutes) minutes"
        } else {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            let hoursStr = h == 1 ? String(localized: "hour") : String(localized: "hours")
            durationStr = m > 0 ? "\(h) \(hoursStr) \(m) minutes" : "\(h) \(hoursStr)"
        }
        let typeStr = isPinned ? String(localized: "Pinned") : String(localized: "Fluid")
        let timeStr = scheduledStart.formatted(.dateTime.hour().minute())
        return "\(title), \(durationStr), \(typeStr), starts at \(timeStr)"
    }
}

// MARK: - Color hex initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
