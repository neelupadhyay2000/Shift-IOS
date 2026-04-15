import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A slide-to-confirm track that prevents accidental block advancement.
///
/// The user must drag the thumb from left to right across >80% of the track
/// width to trigger the `onAdvance` closure. Partial drags snap back with
/// a spring animation. A success haptic fires on completion.
struct SlideToAdvanceView: View {

    /// Called when the user completes the full slide (>80%).
    let onAdvance: () -> Void

    /// Height of the track capsule.
    private let trackHeight: CGFloat = 56
    /// Diameter of the draggable thumb.
    private let thumbSize: CGFloat = 48
    /// Fraction of track width the user must drag to trigger completion.
    static let completionThreshold: CGFloat = 0.8

    @State private var dragOffset: CGFloat = 0
    @State private var isCompleted = false

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let maxOffset = trackWidth - thumbSize - 8 // 4pt inset each side
            let progress = maxOffset > 0 ? min(dragOffset / maxOffset, 1) : 0
            let pastThreshold = progress >= Self.completionThreshold

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                Color.white.opacity(0.12),
                                lineWidth: 0.5
                            )
                    )

                // Fill progress
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: pastThreshold
                                ? [Color.green.opacity(0.5), Color.green.opacity(0.3)]
                                : [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: dragOffset + thumbSize + 4)

                // Label — fades as thumb covers it
                Text(String(localized: "Slide to advance"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .opacity(max(0, 1 - progress * 2.5))

                // Draggable thumb
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Image(systemName: pastThreshold ? "checkmark" : "chevron.right.2")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(pastThreshold ? Color.green : Color.accentColor)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .offset(x: dragOffset + 4)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !isCompleted else { return }
                                dragOffset = max(0, min(value.translation.width, maxOffset))
                            }
                            .onEnded { _ in
                                guard !isCompleted else { return }
                                if progress >= Self.completionThreshold {
                                    completeSlide(maxOffset: maxOffset)
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
    }

    private func completeSlide(maxOffset: CGFloat) {
        isCompleted = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = maxOffset
        }

        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif

        // Brief delay so the user sees the completed state before advancing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onAdvance()
            // Reset for the next block
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = 0
                isCompleted = false
            }
        }
    }
}
