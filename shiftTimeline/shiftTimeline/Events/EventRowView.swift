import SwiftUI
import Models

/// A single row in the event roster list.
/// Displays the event title, formatted date, and a status badge.
struct EventRowView: View {

    let title: String
    let date: Date
    let status: EventStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(date, format: .dateTime.month(.wide).day().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(status.label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.tintColor.opacity(0.15))
                .foregroundStyle(status.tintColor)
                .clipShape(Capsule())
        }
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
