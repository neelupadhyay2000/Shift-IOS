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
            // Left accent bar — thicker, rounded for modern feel
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accentColor.gradient)
                .frame(width: 5)
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(Color(hex: colorTag).opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: colorTag))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(scheduledStart, format: .dateTime.hour().minute())
                            .font(.caption)
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
                HStack(spacing: 3) {
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                    }
                    Text(isPinned ? String(localized: "Pinned") : String(localized: "Fluid"))
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.1))
                .foregroundStyle(accentColor)
                .clipShape(Capsule())
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
