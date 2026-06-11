import SwiftUI
import Models

// MARK: - "Calm pro-tool" colour scheme
//
// Flat, dark-leaning surfaces with hairline borders — typography does the
// work. Tabular numerals for live data; colour is a precise accent, never
// decoration. One restrained accent; emerald is reserved for "go/live";
// amber only for time-of-day (sun) data; everything else is neutral.

enum ShiftPalette {
    /// Interactive/brand accent — calm azure. Used sparingly: key icons, links,
    /// the planning status. Never as a decorative wash.
    static let accent = Color(red: 0.25, green: 0.51, blue: 0.95)
    /// "Go" semantic — live status, the Go Live action, success.
    static let live = Color(red: 0.16, green: 0.74, blue: 0.52)
    /// Time-of-day data only (sunset / golden hour).
    static let warm = Color(red: 0.95, green: 0.64, blue: 0.22)
    /// Quiet/resolved states — completed events, secondary chips.
    static let neutral = Color(red: 0.52, green: 0.55, blue: 0.62)

    /// Soft tint for chip fills behind a coloured glyph or label.
    static func soft(_ color: Color) -> Color { color.opacity(0.13) }
}

// MARK: - Pro Background

/// The calm, cool canvas behind the event surfaces. Dark mode is the signature
/// look — a deep ink, nearly flat; light mode is a cool paper white. Replaces
/// the warm lavender gradient on the event/timeline/live screens.
struct ProBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.067, green: 0.075, blue: 0.094),
                        Color(red: 0.043, green: 0.051, blue: 0.067),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color(red: 0.965, green: 0.969, blue: 0.976)
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

    // MARK: Card Shadows

    /// Standard card shadow — subtle but visible lift.
    static let cardShadow1 = ShadowStyle(color: .black.opacity(0.06), radius: 3, y: 1)
    static let cardShadow2 = ShadowStyle(color: .black.opacity(0.04), radius: 10, y: 5)

    // MARK: Corner Radii

    static let cardRadius: CGFloat = 16
    static let badgeRadius: CGFloat = 8
    static let iconRadius: CGFloat = 12

    // MARK: Role Colors

    static func roleColor(for role: VendorRole) -> Color {
        switch role {
        case .photographer: Color(red: 0.35, green: 0.34, blue: 0.84) // indigo
        case .dj:           Color(red: 0.58, green: 0.25, blue: 0.80) // purple
        case .planner:      Color(red: 0.18, green: 0.60, blue: 0.58) // teal
        case .caterer:      Color(red: 0.90, green: 0.49, blue: 0.13) // orange
        case .florist:      Color(red: 0.30, green: 0.68, blue: 0.31) // green
        case .custom:       Color(red: 0.55, green: 0.55, blue: 0.58) // gray
        }
    }
}

// MARK: - Shadow Style Helper

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

// MARK: - Premium Card Modifier

struct PremiumCardModifier: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: ShiftDesign.cardShadow1.color, radius: ShiftDesign.cardShadow1.radius, y: ShiftDesign.cardShadow1.y)
            .shadow(color: ShiftDesign.cardShadow2.color, radius: ShiftDesign.cardShadow2.radius, y: ShiftDesign.cardShadow2.y)
    }
}

extension View {
    func premiumCard(padding: CGFloat = 14) -> some View {
        modifier(PremiumCardModifier(padding: padding))
    }
}

// MARK: - Warm Background

struct WarmBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.09, blue: 0.12),
                    Color(red: 0.07, green: 0.07, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.95, blue: 0.98),
                    Color(red: 0.94, green: 0.94, blue: 0.97),
                    Color(red: 0.92, green: 0.93, blue: 0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Scroll Transition Modifier

struct ScrollFadeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollTransition(.animated(.easeInOut(duration: 0.3))) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.3)
                    .scaleEffect(phase.isIdentity ? 1 : 0.95)
                    .offset(y: phase.isIdentity ? 0 : 10)
            }
    }
}

extension View {
    func scrollFade() -> some View {
        modifier(ScrollFadeModifier())
    }
}
