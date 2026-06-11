import Models
import SwiftUI

/// "Running N min behind — shift the rest of the day?" banner for the Live
/// Dashboard. Appears once the active block exceeds `OvertimeNudge.threshold`
/// past its scheduled end; the CTA opens the existing quick-shift flow.
/// Dismissable per block — it returns for the next block that runs over.
struct OvertimeNudgeBanner: View {

    let block: TimeBlockModel
    let onShift: () -> Void

    @State private var dismissedForBlockID: UUID?

    private var blockEnd: Date {
        block.scheduledStart.addingTimeInterval(block.duration)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if dismissedForBlockID != block.id,
               let minutes = OvertimeNudge.suggestedMinutes(blockEnd: blockEnd, now: context.date) {
                banner(minutes: minutes)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func banner(minutes: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Running \(minutes) min behind"))
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "Shift the rest of the day?"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                onShift()
            } label: {
                Text(String(localized: "Shift"))
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.orange, in: Capsule())
                    .foregroundStyle(.black)
            }
            .accessibilityIdentifier(AccessibilityID.Live.overtimeShiftButton)
            .accessibilityLabel(String(localized: "Shift timeline"))
            .accessibilityHint(String(localized: "Opens quick shift options"))

            Button {
                dismissedForBlockID = block.id
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel(String(localized: "Dismiss"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.orange.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Live.overtimeNudge)
    }
}
