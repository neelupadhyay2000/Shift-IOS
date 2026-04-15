import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import SwiftData
import Models

// MARK: - LiveDashboardView

/// Event-day execution dashboard.
///
/// All navigation modifiers, lifecycle hooks, and state mutations live here.
/// The visual content is delegated to `_LiveDashboardContent`, which uses
/// `.environment(\.colorScheme, .dark)` — propagating dark mode DOWN only
/// so it does NOT escape to the parent NavigationStack or UIHostingController.
struct LiveDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var results: [EventModel]

    @State private var isShowingExitConfirmation = false

    private let eventID: UUID

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    // MARK: Derived state

    private var event: EventModel? { results.first }

    private var sortedBlocks: [TimeBlockModel] {
        guard let event else { return [] }
        return event.tracks
            .flatMap(\.blocks)
            .sorted(by: { $0.scheduledStart < $1.scheduledStart })
    }

    private var activeBlock: TimeBlockModel? {
        sortedBlocks.first(where: { $0.status == .active })
            ?? sortedBlocks.first(where: { $0.status != .completed })
    }

    private var nextBlock: TimeBlockModel? {
        guard let activeBlock,
              let activeIndex = sortedBlocks.firstIndex(where: { $0.id == activeBlock.id })
        else {
            return sortedBlocks.first(where: { $0.status == .upcoming })
        }
        let tail = sortedBlocks.suffix(from: sortedBlocks.index(after: activeIndex))
        return tail.first(where: { $0.status != .completed })
    }

    // MARK: Body

    var body: some View {
        _LiveDashboardContent(
            event: event,
            activeBlock: activeBlock,
            nextBlock: nextBlock,
            isEventComplete: isEventComplete,
            onAdvance: advanceToNextBlock,
            onDismiss: { dismiss() }
        )
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isShowingExitConfirmation = true
                } label: {
                    Label(String(localized: "Back"), systemImage: "chevron.backward")
                }
            }
        }
        .confirmationDialog(
            String(localized: "Exit live mode?"),
            isPresented: $isShowingExitConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Exit Live Mode"), role: .destructive) {
                exitLiveMode()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        }
        .onAppear {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            activateFirstIncompleteBlockIfNeeded()
        }
        .onDisappear {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
    }

    // MARK: Actions

    private func activateFirstIncompleteBlockIfNeeded() {
        let blocks = sortedBlocks
        guard !blocks.contains(where: { $0.status == .active }) else { return }
        guard let first = blocks.first(where: { $0.status != .completed }) else { return }

        for block in blocks where block.status != .completed {
            block.status = .upcoming
        }
        first.status = .active
        try? modelContext.save()
    }

    private var isEventComplete: Bool {
        guard let event else { return false }
        let allBlocks = event.tracks.flatMap(\.blocks)
        return !allBlocks.isEmpty && allBlocks.allSatisfy { $0.status == .completed }
    }

    private func advanceToNextBlock() {
        Self.performAdvance(
            activeBlock: activeBlock,
            nextBlock: nextBlock,
            event: event
        )
        try? modelContext.save()
    }

    /// Extracted advance logic — testable without a live view hierarchy.
    static func performAdvance(
        activeBlock: TimeBlockModel?,
        nextBlock: TimeBlockModel?,
        event: EventModel?
    ) {
        guard let activeBlock else { return }
        activeBlock.status = .completed

        if let nextBlock {
            nextBlock.status = .active
        } else {
            event?.status = .completed
        }
    }

    private func exitLiveMode() {
        guard let event else {
            dismiss()
            return
        }
        event.status = .planning
        for block in event.tracks.flatMap(\.blocks) where block.status != .completed {
            block.status = .upcoming
        }
        try? modelContext.save()
        dismiss()
    }

}


// MARK: - _LiveDashboardContent

/// Pure layout view. `.environment(\.colorScheme, .dark)` lives only here,
/// propagating dark mode DOWN to children without escaping to the NavigationStack.
private struct _LiveDashboardContent: View {
    let event: EventModel?
    let activeBlock: TimeBlockModel?
    let nextBlock: TimeBlockModel?
    let isEventComplete: Bool
    let onAdvance: () -> Void
    let onDismiss: () -> Void

    private var totalBlocks: Int {
        event?.tracks.flatMap(\.blocks).count ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if let event {
                if isEventComplete {
                    eventCompleteSummary(event: event)
                } else {
                    liveDashboard(event: event)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "Live Event Not Found"),
                    systemImage: "exclamationmark.triangle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WarmBackground() }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Live Dashboard

    private func liveDashboard(event: EventModel) -> some View {
        VStack(spacing: 0) {
            // ── Event title pill ──────────────────────────────────────
            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 16)

            // ── Hero (fills available space) ──────────────────────────
            if let activeBlock {
                ActiveBlockHero(block: activeBlock)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text(String(localized: "No active block"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // ── Next block card ───────────────────────────────────────
            if activeBlock != nil {
                VStack(spacing: 4) {
                    if let nextBlock {
                        Text(String(localized: "Up Next"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        let timeStr = nextBlock.scheduledStart.formatted(.dateTime.hour().minute())
                        Text(String(localized: "Next: \(nextBlock.title) at \(timeStr)"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(String(localized: "Last block of the day"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)
                .animation(.easeInOut(duration: 0.3), value: nextBlock?.id)

                // Slide-to-advance track
                SlideToAdvanceView(onAdvance: onAdvance)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Event Complete Summary

    private func eventCompleteSummary(event: EventModel) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: isEventComplete)

            Text(String(localized: "Event Complete"))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)

            Text(event.title)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)

            // Stats pill
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(totalBlocks)")
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                    Text(String(localized: "Blocks"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text(event.date, format: .dateTime.month().day())
                        .font(.title.weight(.bold))
                    Text(String(localized: "Date"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text(String(localized: "Done"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

// MARK: - Previews

#Preview("System Light") {
    LiveDashboardView(eventID: UUID())
        .environment(\.colorScheme, .light)
}

#Preview("System Dark") {
    LiveDashboardView(eventID: UUID())
        .environment(\.colorScheme, .dark)
}
