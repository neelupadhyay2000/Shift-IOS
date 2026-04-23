import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import SwiftData
import AppIntents
import WidgetKit
import Models
import Engine
import Services

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

    @Environment(WatchSessionManager.self) private var watchSessionManager
    @Environment(LiveActivityManager.self) private var liveActivityManager

    @State private var isShowingExitConfirmation = false
    @State private var isShowingQuickShift = false
    @State private var pendingShiftPreview: ShiftPreview?
    @State private var pendingShiftMinutes: Int = 0
    @State private var undoManager = ShiftUndoManager()

    private let engine = RippleEngine()
    private let previewGenerator = ShiftPreviewGenerator()

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
        return (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingQuickShift = true
                } label: {
                    Label(String(localized: "Shift Timeline"), systemImage: "clock.arrow.circlepath")
                }
                .disabled(isEventComplete)
            }
        }
        .sheet(isPresented: $isShowingQuickShift, onDismiss: {
            if pendingShiftMinutes != 0 {
                showPreview(forMinutes: pendingShiftMinutes)
            }
        }) {
            QuickShiftSheet { minutes in
                pendingShiftMinutes = minutes
                isShowingQuickShift = false
            }
        }
        .sheet(item: previewBinding) { preview in
            ShiftPreviewOverlay(
                preview: preview,
                minutes: pendingShiftMinutes,
                onConfirm: {
                    commitShift(byMinutes: pendingShiftMinutes)
                    pendingShiftMinutes = 0
                    pendingShiftPreview = nil
                },
                onCancel: {
                    pendingShiftMinutes = 0
                    pendingShiftPreview = nil
                }
            )
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
            fetchSunsetIfNeeded()
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
        guard !blocks.contains(where: { $0.status == .active }) else {
            // Already active — still write widget data so the widget
            // has current state after a fresh app launch.
            writeWidgetData()
            return
        }
        guard let first = blocks.first(where: { $0.status != .completed }) else { return }

        for block in blocks where block.status != .completed {
            block.status = .upcoming
        }
        first.status = .active
        do {
            try modelContext.save()
            watchSessionManager.sendCurrentContext()
            writeWidgetData()
        } catch {
            // Save failed — don't push stale context to Watch.
        }
    }

    /// Retries sunset fetch if the event has coordinates but no cached data
    /// (e.g. device was offline when event was created).
    private func fetchSunsetIfNeeded() {
        guard let event,
              event.sunsetTime == nil,
              (event.latitude != 0 && event.longitude != 0) else { return }

        Task { @MainActor in
            let service = SunsetService()
            _ = await service.fetchIfNeeded(for: event)
            try? modelContext.save()
        }
    }

    private var isEventComplete: Bool {
        guard let event else { return false }
        let allBlocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
        return !allBlocks.isEmpty && allBlocks.allSatisfy { $0.status == .completed }
    }

    private func advanceToNextBlock() {
        Self.performAdvance(
            activeBlock: activeBlock,
            nextBlock: nextBlock,
            event: event
        )
        do {
            try modelContext.save()
            watchSessionManager.sendCurrentContext()
            writeWidgetData()
            updateLiveActivity()
        } catch {
            // Save failed — don't push stale context to Watch.
        }
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

    /// Binding that bridges `ShiftPreview?` to `.sheet(item:)`.
    private var previewBinding: Binding<ShiftPreview?> {
        $pendingShiftPreview
    }

    /// Generates a non-mutating preview and stores it for the overlay.
    private func showPreview(forMinutes minutes: Int) {
        guard let active = activeBlock else { return }
        let delta = TimeInterval(minutes * 60)
        let preview = previewGenerator.generatePreview(
            blocks: sortedBlocks,
            blockID: active.id,
            delta: delta
        )
        pendingShiftMinutes = minutes
        pendingShiftPreview = preview
    }

    /// Commits the shift after user confirms the preview.
    ///
    /// 1. Captures undo snapshot before mutation
    /// 2. Calls `RippleEngine.recalculate()` with delta on the active block
    /// 3. Commits undo snapshot after mutation
    /// 4. Persists to SwiftData
    private func commitShift(byMinutes minutes: Int) {
        let delta = TimeInterval(minutes * 60)
        guard let active = activeBlock else { return }
        let blocks = sortedBlocks

        // Phase 1: snapshot before-state for undo
        undoManager.recordShift(blocks: blocks)

        // Phase 2: run the engine — mutates blocks in place
        let result = engine.recalculate(
            blocks: blocks,
            changedBlockID: active.id,
            delta: delta
        )

        // Phase 3: only commit undo if the engine actually applied a shift
        switch result.status {
        case .pinnedBlockCannotShift, .circularDependency:
            undoManager.cancelShift()
            return
        case .clean, .hasCollisions, .impossible:
            undoManager.commitShift(blocks: result.blocks)
        }

        // Phase 4: evaluate per-vendor notification thresholds
        if let event {
            VendorShiftNotifier.applyThresholdNotifications(
                event: event,
                blocks: result.blocks
            )
        }

        do {
            try modelContext.save()
            watchSessionManager.sendCurrentContext()
            writeWidgetData()
            updateLiveActivity()
        } catch {
            // Save failed — don't push stale context to Watch.
        }
    }

    private func exitLiveMode() {
        guard let event else {
            dismiss()
            return
        }

        let resolvedStatus = event.resolveStatusOnExitLiveMode()
        event.status = resolvedStatus

        // Only roll back in-flight block progress when we're reverting the
        // event itself back to planning (user was rehearsing ahead of / after
        // the event day). A genuinely-live event keeps its block progress
        // so re-entering the dashboard restores the user where they left off.
        if resolvedStatus == .planning {
            for block in (event.tracks ?? []).flatMap({ $0.blocks ?? [] })
                where block.status != .completed {
                block.status = .upcoming
            }
        }

        liveActivityManager.end()
        writeNextEventPlaceholder()
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Widget Data

    /// Writes the current live state to App Group UserDefaults so the
    /// home screen widget can display it, then asks WidgetKit to reload.
    private func writeWidgetData() {
        guard let event else { return }

        // Re-derive active/next from the current sorted blocks so we
        // capture the state *after* any mutation.
        let blocks = sortedBlocks
        let active = blocks.first(where: { $0.status == .active })
            ?? blocks.first(where: { $0.status != .completed })

        guard let active else {
            // No remaining blocks — event is complete.
            // End the Live Activity and write a non-live placeholder.
            liveActivityManager.end()
            writeNextEventPlaceholder()
            return
        }

        let nextUp: TimeBlockModel? = {
            guard let idx = blocks.firstIndex(where: { $0.id == active.id }) else { return nil }
            return blocks.suffix(from: blocks.index(after: idx))
                .first(where: { $0.status != .completed })
        }()

        let data = WidgetSharedData(
            activeBlockTitle: active.title,
            blockEndDate: active.scheduledStart.addingTimeInterval(active.duration),
            nextBlockTitle: nextUp?.title,
            nextBlockStartTime: nextUp?.scheduledStart,
            sunsetTime: event.sunsetTime,
            eventID: event.id,
            eventName: event.title,
            isEventLive: true
        )

        WidgetDataStore.save(data)
        reloadShiftWidgetTimelines()
    }

    /// Reloads only the SHIFT widget timelines, not unrelated controls.
    private func reloadShiftWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "shiftTimelineWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "ShiftMediumWidget")
    }

    /// Updates the Lock Screen / Dynamic Island Live Activity with
    /// the current block state. Guards against nil activity.
    private func updateLiveActivity() {
        guard let event else { return }

        let blocks = sortedBlocks
        let active = blocks.first(where: { $0.status == .active })
            ?? blocks.first(where: { $0.status != .completed })

        guard let active else {
            // Event complete — end was already called from writeWidgetData.
            return
        }

        let nextUp: TimeBlockModel? = {
            guard let idx = blocks.firstIndex(where: { $0.id == active.id }) else { return nil }
            return blocks.suffix(from: blocks.index(after: idx))
                .first(where: { $0.status != .completed })
        }()

        liveActivityManager.update(
            currentBlockTitle: active.title,
            blockEndTime: active.scheduledStart.addingTimeInterval(active.duration),
            nextBlockTitle: nextUp?.title,
            sunsetTime: event.sunsetTime
        )
    }

    /// Writes a non-live placeholder with the next upcoming event date
    /// so the widget shows "Next event: …" instead of "No upcoming events".
    private func writeNextEventPlaceholder() {
        let now = Date()
        let descriptor = FetchDescriptor<EventModel>(
            predicate: #Predicate { $0.date >= now },
            sortBy: [SortDescriptor(\EventModel.date)]
        )
        let nextDate = try? modelContext.fetch(descriptor).first?.date
        WidgetDataStore.writeNextEventDate(nextDate)
        reloadShiftWidgetTimelines()
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

    @State private var isSiriTipVisible = true

    private var totalBlocks: Int {
        (event?.tracks ?? []).flatMap { $0.blocks ?? [] }.count
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

            // ── Sunset / Golden Hour banner ───────────────────────────
            if let sunset = event.sunsetTime,
               let golden = event.goldenHourStart {
                SunsetBanner(sunsetTime: sunset, goldenHourStart: golden)
                    .padding(.top, 8)
            }

            // ── Hero (fills available space) ──────────────────────────
            if let activeBlock {
                ActiveBlockHero(block: activeBlock)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ── Vendor quick-contact avatars ────────────────────
                VendorQuickContactRow(vendors: activeBlock.vendors ?? [])
                .padding(.bottom, 8)

                // ── Vendor acknowledgment grid ───────────────────────
                VendorAckGrid(vendors: event.vendors ?? [])
                    .padding(.bottom, 8)
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

                // Siri tip — suggested when event is live
                SiriTipView(intent: ShiftTimelineIntent(), isVisible: $isSiriTipVisible)
                    .siriTipViewStyle(.dark)
                    .padding(.horizontal, 20)

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
        .environment(WatchSessionManager())
        .environment(LiveActivityManager())
        .environment(\.colorScheme, .light)
}

#Preview("System Dark") {
    LiveDashboardView(eventID: UUID())
        .environment(WatchSessionManager())
        .environment(LiveActivityManager())
        .environment(\.colorScheme, .dark)
}
