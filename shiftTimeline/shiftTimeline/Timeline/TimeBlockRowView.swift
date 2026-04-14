import SwiftUI
import Models

/// A single row in the timeline builder list.
/// Displays color accent, icon, title, start time, duration, and a Fluid/Pinned indicator.
struct TimeBlockRowView: View {

    let title: String
    let scheduledStart: Date
    let duration: TimeInterval
    let isPinned: Bool
    let colorTag: String
    let icon: String

    private var accentColor: Color {
        isPinned ? Color(.systemRed) : Color(hex: colorTag)
    }

    var body: some View {
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
