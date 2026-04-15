import SwiftUI

/// Half-sheet with large, thumb-friendly shift buttons (+5, +10, +15, Custom).
///
/// Opened from the LiveDashboard toolbar. Each preset calls `onShift(minutes)`
/// with the selected delta. The Custom option reveals ±5-minute increment buttons
/// clamped to 1…120 minutes.
struct QuickShiftSheet: View {

    /// Called with the number of minutes to shift the timeline.
    let onShift: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isShowingCustom = false
    @State private var customMinutes: Int = 20

    private let presets = [5, 10, 15]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(String(localized: "Shift Timeline"))
                    .font(.title2.weight(.bold))
                    .padding(.top, 8)

                Text(String(localized: "Push all remaining blocks forward"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Preset buttons
                VStack(spacing: 12) {
                    ForEach(presets, id: \.self) { minutes in
                        Button {
                            onShift(minutes)
                            dismiss()
                        } label: {
                            shiftButtonLabel(minutes: minutes)
                        }
                        .buttonStyle(.plain)
                    }

                    // Custom button
                    if isShowingCustom {
                        customEntry
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingCustom = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.title3.weight(.semibold))
                                Text(String(localized: "Custom"))
                                    .font(.title3.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 60)
                            .background(
                                Color.secondary.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Preset Button

    private func shiftButtonLabel(minutes: Int) -> some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3.weight(.semibold))
            Text(String(localized: "+\(minutes) min"))
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 60)
        .background(
            Color.accentColor.opacity(0.15),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - Custom Entry

    private var customEntry: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingCustom = false
                    }
                } label: {
                    Label(String(localized: "Back"), systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(String(localized: "Minutes"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        customMinutes = max(1, customMinutes - 5)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text("\(customMinutes)")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .frame(minWidth: 44)

                    Button {
                        customMinutes = min(120, customMinutes + 5)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            Button {
                onShift(customMinutes)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3.weight(.semibold))
                    Text(String(localized: "+\(customMinutes) min"))
                        .font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 60)
                .background(
                    Color.orange.opacity(0.2),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}
