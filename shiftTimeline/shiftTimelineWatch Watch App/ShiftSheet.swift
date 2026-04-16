import SwiftUI
import Models

/// Dedicated shift screen with large, full-width buttons for quick timeline shifts.
///
/// After tapping, a brief checkmark confirmation is shown without blocking on the
/// iPhone response. The confirmation auto-dismisses after 1.5 seconds.
struct ShiftSheet: View {

    @Environment(WatchSessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var confirmationMinutes: Int?

    var body: some View {
        VStack(spacing: 16) {
            if let minutes = confirmationMinutes {
                confirmationView(minutes: minutes)
            } else {
                shiftButtons
            }
        }
        .navigationTitle(String(localized: "Shift"))
    }

    // MARK: - Shift Buttons

    private var shiftButtons: some View {
        VStack(spacing: 12) {
            Text(String(localized: "Shift Timeline"))
                .font(.headline)
                .padding(.top, 8)

            Button {
                sendShift(minutes: 5)
            } label: {
                Text(String(localized: "+5 min"))
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Button {
                sendShift(minutes: 15)
            } label: {
                Text(String(localized: "+15 min"))
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(.horizontal)
    }

    // MARK: - Confirmation

    private func confirmationView(minutes: Int) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: confirmationMinutes)

            Text(String(localized: "Shifted +\(minutes) min"))
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        }
    }

    // MARK: - Actions

    private func sendShift(minutes: Int) {
        sessionManager.sendShiftCommand(minutes: minutes)
        confirmationMinutes = minutes
    }
}

#Preview {
    NavigationStack {
        ShiftSheet()
            .environment(WatchSessionManager())
    }
}
