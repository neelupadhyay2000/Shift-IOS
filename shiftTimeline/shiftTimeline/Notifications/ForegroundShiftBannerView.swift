import SwiftUI

/// Transient top toast shown in place of a system notification when a shift push
/// arrives while the app is foregrounded.
///
/// `AppDelegate.willPresent` suppresses the system banner for `shift-`
/// notifications and publishes an `InAppShiftBanner` to `DeepLinkRouter`;
/// `RootContainerView` renders this. Tapping deep-links to the event (the same
/// route as tapping the system notification); it otherwise auto-dismisses.
struct ForegroundShiftBannerView: View {

    let banner: InAppShiftBanner
    /// Tapped — deep-link to the event and dismiss.
    let onTap: () -> Void
    /// Auto-dismiss after the display window elapses.
    let onDismiss: () -> Void

    /// How long the banner stays on screen before auto-dismissing.
    private static let visibleDuration: Duration = .seconds(4)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text(banner.body)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.orange, Color.red.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        // Re-arms whenever a new banner (distinct id) is presented.
        .task(id: banner.id) {
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(banner.title). \(banner.body)")
        .accessibilityAddTraits(.isButton)
    }
}
