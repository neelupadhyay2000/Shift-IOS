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
/// The visual content is delegated to `_LiveDashboardContent`, which is the
/// sole owner of `.preferredColorScheme(.dark)` — keeping the dark preference
/// isolated so it does NOT propagate back up the NavigationStack to other screens.
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
            nextBlock: nextBlock
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

/// Pure layout view. `.preferredColorScheme(.dark)` lives only here,
/// preventing it from escaping to the parent NavigationStack.
private struct _LiveDashboardContent: View {
    let event: EventModel?
    let activeBlock: TimeBlockModel?
    let nextBlock: TimeBlockModel?

    var body: some View {
        VStack(spacing: 0) {
            if let event {
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
                    .padding(.bottom, 24)
                    .animation(.easeInOut(duration: 0.3), value: nextBlock?.id)
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
        // Use .environment(\.colorScheme, .dark) — NOT .preferredColorScheme(.dark).
        // preferredColorScheme propagates UP to the UIHostingController/window,
        // forcing the entire app into dark mode and breaking WarmBackground on
        // parent screens. environment(\.colorScheme) propagates DOWN only, so
        // this view and its children (including WarmBackground) see .dark without
        // affecting the NavigationStack above.
        .environment(\.colorScheme, .dark)
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
