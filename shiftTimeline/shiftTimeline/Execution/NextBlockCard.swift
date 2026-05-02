import SwiftUI
import Models

/// Shows the upcoming block's title and start time in the live dashboard.
///
/// Renders "Up Next / {title} at {time}" when a next block exists, or
/// "Last block of the day" when the active block is the final one.
/// Pass `nil` for `nextBlock` to display the end-of-day state.
struct NextBlockCard: View {
    let nextBlock: TimeBlockModel?

    private var accessibilityLabel: String {
        guard let nextBlock else {
            return String(localized: "Last block of the day")
        }
        let timeStr = nextBlock.scheduledStart.formatted(.dateTime.hour().minute())
        return String(localized: "Up next: \(nextBlock.title) at \(timeStr)")
    }

    var body: some View {
        VStack(spacing: 4) {
            if let nextBlock {
                Text(String(localized: "Up Next"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                let timeStr = nextBlock.scheduledStart.formatted(.dateTime.hour().minute())
                Text(String(localized: "Next: \(nextBlock.title) at \(timeStr)"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            } else {
                Text(String(localized: "Last block of the day"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.3), value: nextBlock?.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Previews

#Preview("With next block") {
    let time = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: Date()) ?? Date()
    let block = TimeBlockModel(
        title: "Reception Dinner",
        scheduledStart: time,
        originalStart: time,
        duration: 3600
    )
    return NextBlockCard(nextBlock: block)
        .environment(\.colorScheme, .dark)
        .padding()
        .background(Color.black)
}

#Preview("Last block of the day") {
    NextBlockCard(nextBlock: nil)
        .environment(\.colorScheme, .dark)
        .padding()
        .background(Color.black)
}
