import SwiftUI
import Models

/// Horizontal scrollable tab bar for switching between timeline tracks.
///
/// Shows one pill per track, plus an "All" option. The active tab is
/// visually highlighted with a filled background.
struct TrackTabBar: View {

    let tracks: [TimelineTrack]
    @Binding var selectedTrackID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" tab — shows blocks from every track
                tabButton(
                    label: String(localized: "All"),
                    isSelected: selectedTrackID == nil
                ) {
                    selectedTrackID = nil
                }

                ForEach(tracks) { track in
                    tabButton(
                        label: track.name,
                        isSelected: selectedTrackID == track.id
                    ) {
                        selectedTrackID = track.id
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func tabButton(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .bold : .medium)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor.gradient)
                        : AnyShapeStyle(Color(.tertiarySystemFill))
                )
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.3) : .clear,
                    radius: 6, y: 3
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
