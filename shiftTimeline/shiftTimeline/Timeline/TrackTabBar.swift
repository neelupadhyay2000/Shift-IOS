
import SwiftUI
import Models

/// Horizontal scrollable tab bar for switching between timeline tracks.
///
/// Shows one pill per track, plus an "All" option. The active tab is
/// visually highlighted with a filled background. Scrolls automatically
/// to keep the selected tab visible.
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
        .background(Color(.systemGroupedBackground))
    }

    private func tabButton(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected
                        ? Color.accentColor
                        : Color(.tertiarySystemFill)
                )
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
