import SwiftUI
import Models

/// A single row in the timeline builder list.
/// Displays color dot, title, start time, duration, and a Fluid/Pinned indicator.
struct TimeBlockRowView: View {

    let title: String
    let scheduledStart: Date
    let duration: TimeInterval
    let isPinned: Bool
    let colorTag: String
    let icon: String

    private var accentColor: Color {
        isPinned ? .red : .blue
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 4)
                .padding(.vertical, 2)

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Color(hex: colorTag))
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(scheduledStart, format: .dateTime.hour().minute())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(formattedDuration)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text(isPinned ? String(localized: "Pinned") : String(localized: "Fluid"))
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.15))
                    .foregroundStyle(accentColor)
                    .clipShape(Capsule())
            }
            .padding(.leading, 8)
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
