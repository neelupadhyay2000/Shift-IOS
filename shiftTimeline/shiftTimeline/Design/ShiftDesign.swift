import SwiftUI
import Models

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
