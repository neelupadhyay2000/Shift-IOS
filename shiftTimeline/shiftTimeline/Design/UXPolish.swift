import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Haptics

/// Thin wrapper over UIFeedbackGenerator for premium-feeling micro-interactions.
/// No-ops where UIKit isn't available.
enum Haptics {
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

// MARK: - Shimmer

/// A subtle left-to-right sheen used by skeleton placeholders.
private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.35), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                    .blendMode(.plusLighter)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

// MARK: - Skeleton placeholders

/// A neutral, shimmering block used to build skeleton screens.
struct SkeletonBlock: View {
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 6

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            .frame(height: height)
            .shimmering()
    }
}

/// Skeleton mirroring a `VendorCard` (hero + two text lines) while results load.
struct SkeletonVendorCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                .frame(height: 150)
                .shimmering()
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(height: 16).frame(maxWidth: 160)
                SkeletonBlock(height: 12).frame(maxWidth: 110)
                SkeletonBlock(height: 12).frame(maxWidth: 140)
            }
            .padding(14)
        }
        .proSurface()
    }
}

/// A grid of vendor-card skeletons for the directory's loading state.
struct SkeletonGrid: View {
    let columns: [GridItem]
    var count = 4

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in SkeletonVendorCard() }
        }
        .accessibilityHidden(true)
    }
}
