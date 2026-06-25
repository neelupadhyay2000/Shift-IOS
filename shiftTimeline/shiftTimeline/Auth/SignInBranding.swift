import SwiftUI

// MARK: - Brand palette

/// Brand-splash colors sampled from the app icon — scoped to the sign-in
/// flow, the one fixed-dark "brand moment" in the app. Deliberately not in
/// `ShiftPalette`, whose accent rules forbid decorative washes on the
/// working surfaces.
enum SignInPalette {
    static let indigoTop = Color(red: 0.33, green: 0.27, blue: 0.72)
    static let indigoBottom = Color(red: 0.13, green: 0.10, blue: 0.32)
    /// Primary-action fill — a soft lavender in the icon's indigo family,
    /// deliberately quieter than the icon's mint banner so CTAs sit calmly
    /// on the wash instead of shouting against it.
    static let cta = Color(red: 0.65, green: 0.63, blue: 0.97)
    static let ink = Color(red: 0.06, green: 0.09, blue: 0.13)
    /// The icon's timeline-block colors, left to right.
    static let blocks: [Color] = [
        Color(red: 0.96, green: 0.47, blue: 0.20),
        Color(red: 0.22, green: 0.73, blue: 0.86),
        Color(red: 0.78, green: 0.27, blue: 0.86),
        Color(red: 0.97, green: 0.70, blue: 0.21),
        Color(red: 0.36, green: 0.83, blue: 0.44),
    ]
}

// MARK: - Brand background

/// Deep indigo wash from the icon with a soft glow rising behind the content.
/// Shared by every step of the sign-in flow.
struct SignInBrandBackground: View {
    var body: some View {
        LinearGradient(
            colors: [SignInPalette.indigoTop, SignInPalette.indigoBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RadialGradient(
                colors: [.white.opacity(0.10), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Step badge

/// Lavender circular glyph marking each step of the flow (envelope → key).
/// Purely decorative — hidden from accessibility.
struct SignInStepBadge: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(SignInPalette.ink)
            .frame(width: 62, height: 62)
            .background(SignInPalette.cta, in: Circle())
            .shadow(color: SignInPalette.cta.opacity(0.40), radius: 14, y: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Primary CTA style

/// Lavender-on-ink primary action used across the sign-in flow.
struct SignInPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(SignInPalette.ink.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                SignInPalette.cta.opacity(isEnabled ? 1 : 0.35),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Secondary CTA style

/// Translucent secondary action used alongside ``SignInPrimaryButtonStyle`` —
/// same shape and metrics as the primary CTA so the buttons stack as a
/// consistent set, but quieter (white-on-glass) to preserve hierarchy.
struct SignInSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                .white.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Input field surface

/// Translucent input surface that reads as a field against the indigo wash.
struct SignInFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                .white.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.15))
            }
    }
}

extension View {
    /// Applies the sign-in flow's translucent field surface.
    func signInFieldBackground() -> some View {
        modifier(SignInFieldBackground())
    }
}
