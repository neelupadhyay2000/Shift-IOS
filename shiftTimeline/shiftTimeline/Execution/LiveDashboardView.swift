import SwiftUI
import UIKit
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
            nextBlock: nextBlock,
            formatCountdown: formatCountdown(_:)
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
            UIApplication.shared.isIdleTimerDisabled = true
            activateFirstIncompleteBlockIfNeeded()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
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

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let total = Int(abs(seconds.rounded(.towardZero)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - _LiveDashboardContent

/// Pure layout view. `.preferredColorScheme(.dark)` lives only here,
/// preventing it from escaping to the parent NavigationStack.
private struct _LiveDashboardContent: View {
    let event: EventModel?
    let activeBlock: TimeBlockModel?
    let nextBlock: TimeBlockModel?
    let formatCountdown: (TimeInterval) -> String

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let event {
                    Text(event.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let activeBlock {
                        VStack(spacing: 10) {
                            Text(activeBlock.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)

                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let activeEnd = activeBlock.scheduledStart
                                    .addingTimeInterval(activeBlock.duration)
                                let remaining = activeEnd.timeIntervalSince(context.date)
                                let isOvertime = remaining < 0

                                VStack(spacing: 6) {
                                    Text(formatCountdown(remaining))
                                        .font(.system(size: 74, weight: .bold, design: .monospaced))
                                        .foregroundStyle(isOvertime ? .red : .primary)
                                        .contentTransition(.numericText())

                                    if isOvertime {
                                        Text(String(localized: "OVERTIME"))
                                            .font(.caption.weight(.bold))
                                            .tracking(2)
                                            .foregroundStyle(.red)
                                    } else {
                                        Text(String(localized: "remaining"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Text(String(localized: "No active block"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    if let nextBlock {
                        VStack(spacing: 4) {
                            Text(String(localized: "Next"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(nextBlock.title) • \(nextBlock.scheduledStart, format: .dateTime.hour().minute())")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 8)
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "Live Event Not Found"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background { WarmBackground() }
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
