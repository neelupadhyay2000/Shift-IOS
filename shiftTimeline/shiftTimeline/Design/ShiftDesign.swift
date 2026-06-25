import SwiftUI
import Models

// MARK: - "Calm pro-tool" colour scheme
//
// Flat, dark-leaning surfaces with hairline borders — typography does the
// work. Tabular numerals for live data; colour is a precise accent, never
// decoration. One restrained accent drawn from the app icon's indigo;
// emerald is reserved for "go/live"; amber only for time-of-day (sun)
// data; everything else is neutral.

enum ShiftPalette {
    /// Interactive/brand accent — calm indigo from the app icon. Used
    /// sparingly: key icons, links, the planning status, the global tint.
    /// Never as a decorative wash.
    static let accent = Color(red: 0.46, green: 0.44, blue: 0.90)
    /// "Go" semantic — live status, the Go Live action, success.
    static let live = Color(red: 0.16, green: 0.74, blue: 0.52)
    /// Time-of-day data only (sunset / golden hour).
    static let warm = Color(red: 0.95, green: 0.64, blue: 0.22)
    /// Quiet/resolved states — completed events, secondary chips.
    static let neutral = Color(red: 0.52, green: 0.55, blue: 0.62)

    /// Soft tint for chip fills behind a coloured glyph or label.
    static func soft(_ color: Color) -> Color { color.opacity(0.13) }
}

// MARK: - Spacing scale

/// The single spacing scale for the app. Use these instead of magic numbers so
/// vertical/horizontal rhythm stays consistent screen-to-screen. Section gaps
/// use `xl`/`xxl`; intra-card spacing uses `sm`/`md`.
enum ShiftSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
}

// MARK: - Pro Background

/// The calm, cool canvas behind the event surfaces. Dark mode is the signature
/// look — a deep indigo ink, nearly flat, echoing the app icon; light mode is
/// a faintly lavender paper white. Kept quiet on purpose: the brand hue lives
/// in the cast of the canvas, not in saturated washes.
struct ProBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.082, green: 0.074, blue: 0.132),
                        Color(red: 0.052, green: 0.046, blue: 0.092),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.962, green: 0.955, blue: 0.992),
                        Color(red: 0.928, green: 0.918, blue: 0.978),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Pro Card

/// Card surface: flat fill + hairline border, no glassmorphism.
/// Dark: a slightly lifted ink panel with a white hairline. Light: white with a
/// faint cool border and one soft shadow. The restraint is the style.
struct ProCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 16

    private var fill: Color {
        colorScheme == .dark ? .white.opacity(0.055) : .white
    }

    private var hairline: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07)
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous)
                    .strokeBorder(hairline, lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.05),
                radius: 8, y: 3
            )
    }
}

/// The same flat fill + hairline as ``ProCardModifier`` but with no padding or
/// shadow — for absolutely-sized surfaces like timeline block cards, where the
/// caller owns the frame.
struct ProSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = ShiftDesign.cardRadius

    func body(content: Content) -> some View {
        content
            .background(
                colorScheme == .dark ? Color.white.opacity(0.055) : .white,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.10) : .black.opacity(0.07),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    /// Flat, hairline-bordered card — the standard card surface.
    func proCard(padding: CGFloat = 16) -> some View {
        modifier(ProCardModifier(padding: padding))
    }

    /// Padding-free card surface for caller-sized cards (timeline blocks).
    func proSurface(cornerRadius: CGFloat = ShiftDesign.cardRadius) -> some View {
        modifier(ProSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// Micro-label: the small uppercase tracked caption used for section
    /// headers and data labels.
    func microLabel() -> some View {
        font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Pressable Card Style

/// Tactile press feedback — a subtle spring scale + dim so cards feel
/// responsive. Apply to card-shaped buttons/links: `.buttonStyle(.pressableCard)`.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    static var pressableCard: PressableCardStyle { PressableCardStyle() }
}

// MARK: - Design Tokens

/// Centralized design tokens for the SHIFT app's premium visual identity.
enum ShiftDesign {

    // MARK: Corner Radii

    static let cardRadius: CGFloat = 16
    static let badgeRadius: CGFloat = 8
    static let iconRadius: CGFloat = 12

    // MARK: Role Colors

    /// Single-accent system: role identity reads from the role's SF Symbol
    /// (`VendorRole.systemImage`) + label, never from hue. Every role returns the
    /// one indigo accent so the UI stays restrained (Apple/Linear style). Kept as
    /// a function (not removed) so existing call sites need no signature change.
    static func roleColor(for role: VendorRole) -> Color {
        ShiftPalette.accent
    }
}
