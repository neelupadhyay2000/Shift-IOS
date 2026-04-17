import SwiftUI
import Models

/// A single row in the event roster list.
/// Displays the event title, formatted date, and a status badge.
struct EventRowView: View {

    let title: String
    let date: Date
    let status: EventStatus
    var isShared: Bool = false

    private var statusIcon: String {
        switch status {
        case .planning:  "pencil.and.list.clipboard"
        case .live:      "dot.radiowaves.left.and.right"
        case .completed: "checkmark.seal.fill"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Status icon circle with gradient
            ZStack {
                Circle()
                    .fill(status.tintColor.gradient.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: statusIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(status.tintColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: status == .live)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(date, format: .dateTime.month(.wide).day().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(status.tintColor)
                        .frame(width: 6, height: 6)
                    Text(status.label)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(status.tintColor.opacity(0.1), in: Capsule())
                .foregroundStyle(status.tintColor)

                if isShared {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text(String(localized: "Shared"))
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1), in: Capsule())
                    .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
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
        case .planning:  .orange
        case .live:      .green
        case .completed: .blue
        }
    }
}
