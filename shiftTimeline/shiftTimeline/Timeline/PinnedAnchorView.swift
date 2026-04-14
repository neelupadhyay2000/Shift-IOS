import SwiftUI
import Models

/// Draws fixed-time anchor markers on the timeline for pinned blocks.
///
/// Each pinned block gets a horizontal dashed line with a pin icon
/// and time label extending across the full width of the timeline.
/// These visual anchors help users see which times are locked in.
struct PinnedAnchorView: View {

    let pinnedBlocks: [TimeBlockModel]
    let layout: TimeRulerLayout

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        ForEach(pinnedBlocks) { block in
            let y = layout.yOffset(for: block.scheduledStart)

            HStack(spacing: 4) {
                // Pin icon
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(.systemRed))

                // Time label
                Text(Self.timeFormatter.string(from: block.scheduledStart))
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(.systemRed).opacity(0.8))

                // Dashed line extending to the right
                DashedLine()
                    .stroke(
                        Color(.systemRed).opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                    .frame(height: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: y - 5)
        }
    }
}

// MARK: - Dashed Line Shape

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
