import SwiftUI
import SwiftData
import Models

/// Prominent banner shown to vendors when the timeline has shifted since
/// their last acknowledgment. Not swipe-dismissable — the vendor must
/// explicitly tap to confirm they've seen the change.
///
/// Tapping sets `hasAcknowledgedLatestShift = true` and clears
/// `pendingShiftDelta` on the vendor's record, which syncs back to
/// CloudKit so the planner's acknowledgment grid updates.
struct ShiftAcknowledgmentBanner: View {

    @Environment(\.modelContext) private var modelContext
    @Bindable var vendor: VendorModel

    private var formattedDelta: String {
        guard let delta = vendor.pendingShiftDelta else { return "" }
        let minutes = Int(delta / 60)
        let sign = minutes >= 0 ? "+" : ""
        return "\(sign)\(minutes) min"
    }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                vendor.hasAcknowledgedLatestShift = true
                vendor.pendingShiftDelta = nil
                try? modelContext.save()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Timeline updated \(formattedDelta)",
                                comment: "Banner title showing shift delta e.g. Timeline updated +15 min"))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(String(localized: "Tap to acknowledge.",
                                comment: "Banner subtitle prompting vendor to tap"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.orange, Color.red.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(localized: "Timeline updated \(formattedDelta). Tap to acknowledge.",
                   comment: "Accessibility label for shift acknowledgment banner")
        )
    }
}
