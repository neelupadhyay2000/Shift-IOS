import SwiftUI
import Models

// MARK: - Context

/// Data required to present the transit block insertion prompt.
struct TransitPromptContext: Identifiable {
    let id = UUID()
    let originBlock: TimeBlockModel
    let destinationBlock: TimeBlockModel
    /// Calculated driving time in minutes. `nil` means the service failed — show the fallback UI.
    let travelMinutes: Int?
}

// MARK: - View

/// Half-sheet prompt asking the user whether to insert an auto-calculated transit block
/// between two consecutive blocks that have different venue locations.
struct TransitBlockPromptView: View {

    let context: TransitPromptContext
    /// Called with the resolved minute count when the user taps "Add".
    let onAdd: (Int) -> Void
    /// Called when the user taps "Skip".
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fallbackMinutesText: String = "15"

    private var resolvedMinutes: Int {
        context.travelMinutes ?? (Int(fallbackMinutesText) ?? 15)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Spacer()
                    Image(systemName: "car.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color(hex: "#8E8E93"))
                    Spacer()
                }
                .padding(.top, 8)

                if let minutes = context.travelMinutes {
                    normalPrompt(minutes: minutes)
                } else {
                    fallbackPrompt
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle(String(localized: "Transit Block"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Add")) {
                        onAdd(resolvedMinutes)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Skip")) {
                        onSkip()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sub-views

    private func normalPrompt(minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                String(
                    localized: "Add \(minutes)-min transit block?",
                    comment: "Transit block prompt — shows calculated driving minutes"
                )
            )
            .font(.title3.weight(.semibold))
            Text(
                String(
                    localized: "Between \"\(context.originBlock.title)\" and \"\(context.destinationBlock.title)\".",
                    comment: "Transit block prompt — names the two venue blocks"
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fallbackPrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Couldn't calculate travel time."))
                .font(.title3.weight(.semibold))
            Text(String(localized: "Add a manual transit block?"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text(String(localized: "Duration (minutes)"))
                    .font(.subheadline)
                Spacer()
                TextField("15", text: $fallbackMinutesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
