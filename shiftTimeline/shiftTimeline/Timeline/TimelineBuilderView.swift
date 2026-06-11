import CoreLocation
import SwiftUI
import SwiftData
import TipKit
import Models
import Services

/// Displays a vertical timeline of time blocks for a given event.
///
/// Layout: thin ruler on the left, block cards on the right, positioned
/// by `scheduledStart` within a scrollable fixed-height frame.
/// Compact mode reduces scale so the full timeline fits without scrolling.
struct TimelineBuilderView: View {

    @Query private var results: [EventModel]

    private let eventID: UUID

    init(eventID: UUID) {
        self.eventID = eventID
        _results = Query(
            filter: #Predicate<EventModel> { $0.id == eventID }
        )
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SupabaseAuthService.self) private var authService
    @Environment(\.eventRepository) private var injectedEventRepo
    @Environment(\.trackRepository) private var injectedTrackRepo
    @Environment(\.blockRepository) private var injectedBlockRepo

    private var eventRepo: any EventRepositing {
        injectedEventRepo ?? SwiftDataEventRepository(context: modelContext)
    }
    private var trackRepo: any TrackRepositing {
        injectedTrackRepo ?? SwiftDataTrackRepository(context: modelContext)
    }
    private var blockRepo: any BlockRepositing {
        injectedBlockRepo ?? SwiftDataBlockRepository(context: modelContext)
    }

    @State private var undoManager = ShiftUndoManager()
    @State private var isShowingCreateSheet = false
    @State private var blockToInspect: TimeBlockModel?
    @State private var blockPendingDeletion: TimeBlockModel?
    @State private var isInspectorOpen = false

    @State private var isEditing = false
    // Bumped on every committed reorder so `.sensoryFeedback` fires a tap on drop.
    @State private var reorderTick = 0

    // Track management
    @State private var isShowingAddTrackAlert = false
    @State private var newTrackName = ""
    @State private var trackToRename: TimelineTrack?
    @State private var renameText = ""
    @State private var trackToDelete: TimelineTrack?

    // Track filtering — nil means "All", otherwise filters to a specific track
    @State private var selectedTrackID: UUID?

    // Voice memo recording
    @State private var blockForRecording: TimeBlockModel?

    // Paywall
    @State private var isShowingPaywall = false

    // Tips
    private let addBlockTip = AddBlockTip()
    private let reorderTip = ReorderBlockTip()
    private let pinnedTip = PinnedBlockTip()

    // Transit block prompt
    @State private var transitPromptContext: TransitPromptContext?
    @State private var skippedVenuePairs: Set<String> = []
    @State private var transitCheckTask: Task<Void, Never>?
    @State private var travelTimeService = TravelTimeService()

    private var event: EventModel? { results.first }

    /// Vendors viewing an event shared to them get a read-only timeline — no
    /// add/edit/move/delete affordances. The owner edits as before.
    private var isReadOnly: Bool {
        EventAccess.isShared(ownerId: event?.ownerId, currentProfileID: authService.currentProfileID)
    }

    /// The signed-in vendor's profile when viewing a shared event, else `nil`.
    /// Drives the per-block "Assigned" indicator (owners get `nil` — no badge).
    private var viewerProfileID: UUID? {
        isReadOnly ? authService.currentProfileID : nil
    }

    /// On iPhone (compact), this binding drives the `.sheet(item:)`.
    /// On iPad (regular), it returns `.constant(nil)` so the sheet never fires.
    private var sheetBinding: Binding<TimeBlockModel?> {
        if sizeClass == .compact {
            return $blockToInspect
        } else {
            return .constant(nil)
        }
    }

    /// Live-reads blocks from SwiftData relationships — never stale.
    private var sortedBlocks: [TimeBlockModel] {
        guard let event else { return [] }
        return (event.tracks ?? [])
            .flatMap { $0.blocks ?? [] }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    /// All tracks for this event, sorted by sortOrder.
    private var sortedTracks: [TimelineTrack] {
        (event?.tracks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// The default track — identified by the stable `isDefault` flag,
    /// not by name. Cannot be renamed or deleted.
    private var defaultTrack: TimelineTrack? {
        sortedTracks.first { $0.isDefault }
    }

    /// Blocks filtered by the selected track tab.
    /// When `selectedTrackID` is nil ("All"), shows all blocks.
    private var filteredBlocks: [TimeBlockModel] {
        guard let trackID = selectedTrackID else { return sortedBlocks }
        return sortedBlocks.filter { $0.track?.id == trackID }
    }

    private var hasPinnedBlock: Bool {
        sortedBlocks.contains { $0.isPinned }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // iPhone compact: show track tab bar when multiple tracks
            if sizeClass == .compact && sortedTracks.count > 1 {
                TrackTabBar(tracks: sortedTracks, selectedTrackID: $selectedTrackID)
                    .accessibilityIdentifier(AccessibilityID.Timeline.trackTabBar)
            }

            // Reorder mode banner — slides in when isEditing is active
            if isEditing {
                editModeBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                if sizeClass == .compact {
                    // iPhone: single-track filtered view
                    if filteredBlocks.isEmpty {
                        emptyState
                    } else if isEditing {
                        // Edit mode swaps the proportional canvas for a uniform,
                        // scrollable, natively reorderable list — reordering stays
                        // predictable regardless of block durations or time gaps.
                        reorderListContent
                    } else {
                        timelineContent
                    }
                } else {
                    // iPad: side-by-side multi-column view
                    if sortedBlocks.isEmpty {
                        emptyState
                    } else {
                        iPadMultiColumnContent
                    }
                }
            }
        }
        .onAppear {
            if hasPinnedBlock { PinnedBlockTip.hasPinnedBlock = true }
        }
        .onChange(of: hasPinnedBlock) { _, newValue in
            if newValue { PinnedBlockTip.hasPinnedBlock = true }
        }
        .navigationTitle(event?.title ?? String(localized: "Timeline"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !isReadOnly { toolbarItems } }
        .sheet(isPresented: $isShowingCreateSheet, onDismiss: { scanForVenueSwitches() }) {
            CreateBlockSheet(
                eventID: eventID,
                trackID: selectedTrackID,
                suggestedStartTime: sortedBlocks.isEmpty ? nil : nextAvailableStartTime
            )
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(trigger: .blockLimit)
        }
        // iPhone: sheet presentation
        .sheet(item: sheetBinding, onDismiss: { scanForVenueSwitches() }) { block in
            // Vendors get a dedicated, scrollable read-only detail; owners get the
            // editing inspector. (A disabled editing Form couldn't be scrolled.)
            if isReadOnly {
                BlockDetailReadOnlyView(block: block, eventID: eventID)
                    .presentationDetents([.medium, .large])
            } else {
                BlockInspectorView(block: block, eventID: eventID, isInspectorMode: false, isReadOnly: false)
                    .presentationDetents([.medium, .large])
            }
        }
        // Voice memo recording sheet
        .sheet(item: $blockForRecording) { block in
            VoiceMemoRecordingSheet(block: block)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        // Transit block prompt — fires whenever a venue location changes anywhere
        // in the timeline (new block saved, inspector edit, etc).
        .sheet(item: $transitPromptContext) { ctx in
            TransitBlockPromptView(
                context: ctx,
                onAdd: { minutes in
                    insertTransitBlock(minutes: minutes, after: ctx.originBlock, before: ctx.destinationBlock)
                },
                onSkip: {
                    skippedVenuePairs.insert(pairKey(origin: ctx.originBlock, destination: ctx.destinationBlock))
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: venueFingerprint) { _, _ in
            scanForVenueSwitches()
        }
        // iPad: trailing inspector panel
        .inspector(isPresented: $isInspectorOpen) {
            if let block = blockToInspect {
                if isReadOnly {
                    BlockDetailReadOnlyView(block: block, eventID: eventID, isInspectorMode: true)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                } else {
                    BlockInspectorView(block: block, eventID: eventID, isInspectorMode: true, isReadOnly: false)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                }
            }
        }
        .onChange(of: blockToInspect) { _, newValue in
            if sizeClass != .compact {
                isInspectorOpen = newValue != nil
            }
        }
        .onChange(of: isInspectorOpen) { _, isOpen in
            if !isOpen {
                blockToInspect = nil
                // iPad live-write inspector closed — re-scan in case venue changed.
                scanForVenueSwitches()
                if event != nil {
                    Task { try? await eventRepo.save() }
                }
            }
        }
        .alert(
            String(localized: "Delete Pinned Block"),
            isPresented: Binding(
                get: { blockPendingDeletion != nil },
                set: { if !$0 { blockPendingDeletion = nil } }
            )
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                if let block = blockPendingDeletion {
                    deleteBlock(block)
                    blockPendingDeletion = nil
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                blockPendingDeletion = nil
            }
        } message: {
            if blockPendingDeletion != nil {
                Text(String(localized: "This block is pinned. Deleting it may affect the timeline. Are you sure?"))
            }
        }
        // Add Track alert
        .alert(String(localized: "New Track"), isPresented: $isShowingAddTrackAlert) {
            TextField(String(localized: "Track Name"), text: $newTrackName)
            Button(String(localized: "Add")) { addTrack() }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "Enter a name for the new track."))
        }
        // Rename Track alert
        .alert(String(localized: "Rename Track"), isPresented: Binding(
            get: { trackToRename != nil },
            set: { if !$0 { trackToRename = nil } }
        )) {
            TextField(String(localized: "Track Name"), text: $renameText)
            Button(String(localized: "Rename")) { renameTrack() }
            Button(String(localized: "Cancel"), role: .cancel) { trackToRename = nil }
        }
        // Delete Track confirmation alert
        .alert(
            String(localized: "Delete Track"),
            isPresented: Binding(
                get: { trackToDelete != nil },
                set: { if !$0 { trackToDelete = nil } }
            )
        ) {
            Button(String(localized: "Delete"), role: .destructive) { deleteTrack() }
            Button(String(localized: "Cancel"), role: .cancel) { trackToDelete = nil }
        } message: {
            if let track = trackToDelete, !(track.blocks ?? []).isEmpty {
                Text(String(localized: "This track has \((track.blocks ?? []).count) blocks. They will be moved to Main."))
            } else {
                Text(String(localized: "Are you sure you want to delete this track?"))
            }
        }
        .onAppear {
            // Default to Main track on first appearance
            if selectedTrackID == nil, let main = defaultTrack {
                selectedTrackID = main.id
            }
        }
        .onDisappear {
            // Auto-exit edit mode so it doesn't persist across navigation
            isEditing = false
        }
        // Native haptic feedback whenever edit mode is toggled
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: isEditing)
    }

    // MARK: - Edit Mode Banner

    /// A persistent contextual banner that slides in below the navigation bar
    /// when reorder mode is active. Communicates drag affordances and the
    /// pinned-block constraint without occupying a modal surface.
    private var editModeBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, isActive: isEditing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Reorder Mode"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(String(localized: "Drag the handle to reorder · pinned blocks stay fixed"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.06))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Reorder mode active. Drag fluid blocks to rearrange. Pinned blocks are fixed."))
    }

    // MARK: - Timeline Content

    /// Layout computed from the currently visible (filtered) blocks — used by iPhone.
    private var layout: TimeRulerLayout {
        .adaptive(blocks: filteredBlocks)
    }

    /// Layout computed from ALL blocks across ALL tracks — used by iPad
    /// so the shared ruler spans the full time range.
    private var sharedLayout: TimeRulerLayout {
        .adaptive(blocks: sortedBlocks)
    }

    /// Pinned blocks for anchor markers.
    private var pinnedBlocks: [TimeBlockModel] {
        sortedBlocks.filter(\.isPinned)
    }

    /// The next available start time: the end of the last block across all tracks,
    /// kept on the same calendar date as the event. Falls back to `Date.now` when
    /// no blocks exist yet.
    private var nextAvailableStartTime: Date {
        guard let event,
              let lastBlock = sortedBlocks.max(by: { 
                  ($0.scheduledStart + $0.duration) < ($1.scheduledStart + $1.duration)
              }) else {
            return .now
        }
        let candidate = lastBlock.scheduledStart.addingTimeInterval(lastBlock.duration)
        // Keep the candidate on the event's calendar date by preserving only the
        // time components and combining them with the event date.
        let calendar = Calendar.current
        let candidateComponents = calendar.dateComponents([.hour, .minute], from: candidate)
        let eventDateComponents = calendar.dateComponents([.year, .month, .day], from: event.date)
        var merged = DateComponents()
        merged.year = eventDateComponents.year
        merged.month = eventDateComponents.month
        merged.day = eventDateComponents.day
        merged.hour = candidateComponents.hour
        merged.minute = candidateComponents.minute
        merged.second = 0
        return calendar.date(from: merged) ?? candidate
    }

    /// iPhone: single-track timeline with filter tabs.
    private var timelineContent: some View {
        ScrollView {
            TipView(reorderTip)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .task {
                    try? await Task.sleep(for: .seconds(5))
                    reorderTip.invalidate(reason: .tipClosed)
                }
            TipView(pinnedTip)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .task(id: hasPinnedBlock) {
                    guard hasPinnedBlock else { return }
                    try? await Task.sleep(for: .seconds(5))
                    pinnedTip.invalidate(reason: .tipClosed)
                }

            let currentLayout = layout
            let blocks = filteredBlocks
            let maxYMap = nextBlockYMap(for: blocks, layout: currentLayout)

            ZStack(alignment: .topLeading) {
                // Full-width guide lines at every marker — decorative only
                ForEach(currentLayout.hourMarkers, id: \.self) { marker in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(height: 0.5)
                        .offset(y: currentLayout.yOffset(for: marker) - 3)
                        .accessibilityHidden(true)
                }

                // Pinned block anchor lines
                PinnedAnchorView(pinnedBlocks: pinnedBlocks, layout: currentLayout)
                    .accessibilityHidden(true)

                // Golden hour / sunset markers — accessible via VoiceOver
                SunsetMarkerView(
                    goldenHourStart: event?.goldenHourStart,
                    sunsetTime: event?.sunsetTime,
                    layout: currentLayout
                )

                HStack(alignment: .top, spacing: 0) {
                    TimeRulerView(
                        layout: currentLayout,
                        suppressedDates: (
                            [event?.goldenHourStart, event?.sunsetTime].compactMap { $0 }
                            + pinnedBlocks.map(\.scheduledStart)
                        )
                    )
                    .accessibilityHidden(true)

                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(height: currentLayout.totalHeight)

                        ForEach(blocks) { block in
                            blockCard(block, in: currentLayout, maxY: maxYMap[block.id])
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
            .padding(.trailing, 16)
        }
        .scrollDisabled(isEditing)
        .scrollIndicators(.hidden)
        .background { ProBackground() }
        .accessibilityIdentifier(AccessibilityID.Timeline.blockList)
    }

    /// iPad: multi-column layout with shared time ruler and side-by-side track columns.
    private var iPadMultiColumnContent: some View {
        ScrollView {
            let currentLayout = sharedLayout

            ZStack(alignment: .topLeading) {
                // Full-width hour guide lines — decorative only
                ForEach(currentLayout.hourMarkers, id: \.self) { hour in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(height: 0.5)
                        .offset(y: currentLayout.yOffset(for: hour) - 3)
                        .accessibilityHidden(true)
                }

                // Pinned block anchor lines
                PinnedAnchorView(pinnedBlocks: pinnedBlocks, layout: currentLayout)
                    .accessibilityHidden(true)

                // Golden hour / sunset markers — accessible via VoiceOver
                SunsetMarkerView(
                    goldenHourStart: event?.goldenHourStart,
                    sunsetTime: event?.sunsetTime,
                    layout: currentLayout
                )

                HStack(alignment: .top, spacing: 0) {
                    TimeRulerView(
                        layout: currentLayout,
                        suppressedDates: (
                            [event?.goldenHourStart, event?.sunsetTime].compactMap { $0 }
                            + pinnedBlocks.map(\.scheduledStart)
                        )
                    )
                    .accessibilityHidden(true)

                    HStack(alignment: .top, spacing: 8) {
                        ForEach(sortedTracks) { track in
                            TrackColumnView(
                                track: track,
                                layout: currentLayout,
                                isReadOnly: isReadOnly,
                                isEditing: isEditing,
                                viewerProfileID: viewerProfileID,
                                onTapBlock: { block in blockToInspect = block },
                                onDeleteBlock: { block in
                                    if block.isPinned {
                                        blockPendingDeletion = block
                                    } else {
                                        deleteBlock(block)
                                    }
                                },
                                onReorderBlock: { block, dropY, trackBlocks in
                                    reorderBlock(block, toY: dropY, blocks: trackBlocks, in: currentLayout)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
            .padding(.trailing, 16)
        }
        .scrollDisabled(isEditing)
        .scrollIndicators(.hidden)
        .background { ProBackground() }
    }

    // MARK: - Reorder List (iPhone edit mode)

    /// Uniform, scrollable, natively reorderable list shown on iPhone while
    /// editing. Replacing the time-proportional canvas here is what makes
    /// reordering smooth: every row is the same height (no giant blocks to drag
    /// across), the list scrolls and auto-scrolls during a drag, and SwiftUI's
    /// built-in move animation handles the reflow. Pinned blocks are shown for
    /// context but cannot be moved.
    private var reorderListContent: some View {
        List {
            ForEach(filteredBlocks) { block in
                reorderRow(block)
                    .moveDisabled(block.isPinned || isReadOnly)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onMove(perform: moveBlocks)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background { ProBackground() }
        // Smooths the reflow when a pinned anchor re-sorts a block after the drop,
        // on top of the List's native drag-and-drop move animation.
        .animation(.snappy(duration: 0.28), value: filteredBlocks.map(\.id))
        // A single confident tap confirms the drop landed.
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: reorderTick)
    }

    private func reorderRow(_ block: TimeBlockModel) -> some View {
        TimeBlockRowView(
            title: block.title,
            scheduledStart: block.scheduledStart,
            duration: block.duration,
            isPinned: block.isPinned,
            colorTag: block.colorTag,
            icon: block.icon,
            isCompact: false
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .proSurface()
        .overlay {
            if !block.isPinned {
                RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous)
                    .strokeBorder(ShiftPalette.accent.opacity(0.35), lineWidth: 1)
            }
        }
        .opacity(block.isPinned ? 0.6 : 1)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            block.isPinned
                ? String(localized: "\(block.title), pinned, fixed position")
                : String(localized: "\(block.title), drag to reorder")
        )
    }

    private func blockCard(
        _ block: TimeBlockModel,
        in currentLayout: TimeRulerLayout,
        maxY: CGFloat? = nil
    ) -> some View {
        let yOffset = currentLayout.yOffset(for: block.scheduledStart)
        let durationHeight = currentLayout.height(for: block.duration)
        let useCompact = durationHeight < 50
        let minHeight: CGFloat = useCompact ? 32 : 52
        let naturalHeight = max(durationHeight, minHeight)
        let height: CGFloat = {
            guard !useCompact, let maxY else { return naturalHeight }
            let gap = maxY - yOffset
            return gap > 4 ? min(naturalHeight, gap - 2) : naturalHeight
        }()

        let isAssignedToViewer = block.isAssigned(to: viewerProfileID)

        return Button {
            blockToInspect = block
        } label: {
            HStack(spacing: 0) {
                TimeBlockRowView(
                    title: block.title,
                    scheduledStart: block.scheduledStart,
                    duration: block.duration,
                    isPinned: block.isPinned,
                    colorTag: block.colorTag,
                    icon: block.icon,
                    isCompact: useCompact,
                    isAssignedToViewer: isAssignedToViewer
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .proSurface()
            // Emerald halo so a vendor's own blocks pop out of the timeline at a glance.
            .overlay {
                if isAssignedToViewer {
                    RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous)
                        .strokeBorder(ShiftPalette.live.opacity(0.8), lineWidth: 1.5)
                }
            }
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isReadOnly ? "" : String(localized: "Double-tap to edit. Use context menu to delete."))
        .contextMenu {
            if !isReadOnly && !isEditing {
                Button {
                    blockToInspect = block
                } label: {
                    Label(String(localized: "Edit"), systemImage: "pencil")
                }

                if block.voiceMemoURL == nil {
                    Button {
                        blockToInspect = nil
                        blockForRecording = block
                    } label: {
                        Label(String(localized: "Record Voice Memo"), systemImage: "mic")
                    }
                } else {
                    Button {
                        blockToInspect = block
                    } label: {
                        Label(String(localized: "Play Voice Memo"), systemImage: "play.circle")
                    }
                    Button(role: .destructive) {
                        deleteVoiceMemo(for: block)
                    } label: {
                        Label(String(localized: "Delete Voice Memo"), systemImage: "waveform.slash")
                    }
                }

                Button(role: .destructive) {
                    if block.isPinned {
                        blockPendingDeletion = block
                    } else {
                        deleteBlock(block)
                    }
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
            }
        }
        .padding(.leading, 4)
        .offset(y: yOffset)
    }

    private func nextBlockYMap(for blocks: [TimeBlockModel], layout: TimeRulerLayout) -> [UUID: CGFloat] {
        var map = [UUID: CGFloat]()
        for index in blocks.indices where index + 1 < blocks.count {
            map[blocks[index].id] = layout.yOffset(for: blocks[index + 1].scheduledStart)
        }
        return map
    }


    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // + button — hidden while in edit/reorder mode
        if !isEditing {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if sortedBlocks.count >= FreeTier.maxBlocksPerEvent && !SubscriptionManager.shared.isProUser {
                        isShowingPaywall = true
                    } else {
                        isShowingCreateSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .popoverTip(addBlockTip, arrowEdge: .top)
                .task(id: AddBlockTip.hasCreatedFirstEvent) {
                    guard AddBlockTip.hasCreatedFirstEvent else { return }
                    try? await Task.sleep(for: .seconds(5))
                    addBlockTip.invalidate(reason: .tipClosed)
                }
                .accessibilityLabel(String(localized: "Add Block"))
                .accessibilityIdentifier(AccessibilityID.Timeline.addBlockButton)
            }
        }

        // Edit / Done toggle — both iPhone and iPad
        ToolbarItem(placement: isEditing ? .primaryAction : .topBarTrailing) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isEditing.toggle()
                }
            } label: {
                if isEditing {
                    Text(String(localized: "Done"))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(String(localized: "Edit"))
                        .foregroundStyle(Color.secondary)
                }
            }
            .contentTransition(.identity)
            .accessibilityLabel(
                isEditing
                    ? String(localized: "Finish reordering")
                    : String(localized: "Reorder blocks")
            )
        }

        // Tracks menu — hidden while in edit/reorder mode
        if !isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        newTrackName = ""
                        isShowingAddTrackAlert = true
                    } label: {
                        Label(String(localized: "Add Track"), systemImage: "plus.rectangle.on.rectangle")
                    }

                    if sortedTracks.count > 1 {
                        Divider()
                        ForEach(sortedTracks) { track in
                            Menu(track.name) {
                                // Default track cannot be renamed or deleted
                                if !track.isDefault {
                                    Button {
                                        renameText = track.name
                                        trackToRename = track
                                    } label: {
                                        Label(String(localized: "Rename"), systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        trackToDelete = track
                                    } label: {
                                        Label(String(localized: "Delete"), systemImage: "trash")
                                    }
                                }
                            }
                            // Don't show a submenu at all for the default track
                            // if it has no actions — but keep it listed for visibility
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.stack")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .accessibilityLabel(String(localized: "Manage Tracks"))
            }
        }

        // iPad: visible undo/redo toolbar buttons (touch-friendly)
        if sizeClass != .compact {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 4) {
                    Button {
                        undoManager.undo(applying: sortedBlocks)
                        AnalyticsService.send(.undoUsed)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!undoManager.canUndo)
                    .accessibilityLabel(String(localized: "Undo"))

                    Button {
                        undoManager.redo(applying: sortedBlocks)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!undoManager.canRedo)
                    .accessibilityLabel(String(localized: "Redo"))
                }
            }
        }

        // iPad keyboard shortcuts — Cmd+Z, Cmd+Shift+Z, Cmd+S, Cmd+N
        ToolbarItem(placement: .keyboard) {
            Button {
                undoManager.undo(applying: sortedBlocks)
                AnalyticsService.send(.undoUsed)
            } label: {
                Label(String(localized: "Undo"), systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!undoManager.canUndo)
        }
        ToolbarItem(placement: .keyboard) {
            Button {
                undoManager.redo(applying: sortedBlocks)
            } label: {
                Label(String(localized: "Redo"), systemImage: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!undoManager.canRedo)
        }
        ToolbarItem(placement: .keyboard) {
            Button {
                Task { try? await eventRepo.save() }
            } label: {
                Label(String(localized: "Save"), systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
        }
        ToolbarItem(placement: .keyboard) {
            Button {
                isShowingCreateSheet = true
            } label: {
                Label(String(localized: "New Block"), systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                isReadOnly
                    ? String(localized: "No blocks yet")
                    : String(localized: "Add your first block"),
                systemImage: "clock.badge.plus"
            )
        } actions: {
            if !isReadOnly {
                Button(String(localized: "Add Block")) {
                    isShowingCreateSheet = true
                }
            }
        }
    }

    // MARK: - Track Management

    private func addTrack() {
        let trimmed = newTrackName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let event else { return }

        let nextOrder = (sortedTracks.last?.sortOrder ?? 0) + 1
        let track = TimelineTrack(name: trimmed, sortOrder: nextOrder, event: event)
        Task { try? await trackRepo.insert(track, into: event) }
    }

    private func renameTrack() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let track = trackToRename else { return }
        track.name = trimmed
        trackToRename = nil
    }

    private func deleteTrack() {
        guard let track = trackToDelete, !track.isDefault else {
            trackToDelete = nil
            return
        }

        // If deleting the currently selected track, switch to default
        if selectedTrackID == track.id {
            selectedTrackID = defaultTrack?.id
        }

        // Move blocks to default track before deleting
        if !(track.blocks ?? []).isEmpty, let main = defaultTrack {
            for block in track.blocks ?? [] {
                block.track = main
            }
        }

        Task { try? await trackRepo.delete(track) }
        trackToDelete = nil
    }

    // MARK: - Reorder

    /// iPad / Y-based reorder: maps a drop position to an insertion index, then
    /// commits the new order through `applyReorder`. Insertion compares against
    /// each block's vertical midpoint so dropping over a tall block lands where
    /// the finger actually is, not at its top edge.
    private func reorderBlock(
        _ block: TimeBlockModel,
        toY dropY: CGFloat,
        blocks orderedBlocks: [TimeBlockModel],
        in currentLayout: TimeRulerLayout
    ) {
        guard !block.isPinned else { return }
        guard orderedBlocks.count > 1 else { return }

        var blocks = orderedBlocks
        blocks.removeAll { $0.id == block.id }

        var insertionIndex = blocks.count
        for (index, other) in blocks.enumerated() {
            let otherMidpoint = currentLayout.yOffset(for: other.scheduledStart)
                + currentLayout.height(for: other.duration) / 2
            if dropY < otherMidpoint {
                insertionIndex = index
                break
            }
        }

        blocks.insert(block, at: insertionIndex)
        applyReorder(blocks)
    }

    /// iPhone list reorder: applies the `List`'s native move, then commits the
    /// new order through the shared recompute.
    private func moveBlocks(from source: IndexSet, to destination: Int) {
        guard !isReadOnly else { return }
        var ordered = filteredBlocks
        ordered.move(fromOffsets: source, toOffset: destination)
        applyReorder(ordered)
        reorderTick += 1
    }

    /// Recomputes `scheduledStart` for a reordered sequence and persists it.
    ///
    /// Fluid blocks are packed contiguously; pinned blocks keep their fixed clock
    /// time and act as anchors. Crucially, the walk starts from the timeline's
    /// *actual earliest start* — not `event.date`, which carries an arbitrary
    /// time-of-day (the event picker is date-only) and would fling the whole
    /// fluid chain away from the pinned anchors, opening a large gap on the
    /// proportional canvas.
    private func applyReorder(_ ordered: [TimeBlockModel]) {
        guard ordered.count > 1 else { return }

        undoManager.recordShift(blocks: ordered)

        let anchor = ordered.map(\.scheduledStart).min() ?? ordered[0].scheduledStart
        var cursor = anchor
        for current in ordered {
            if current.isPinned {
                cursor = max(cursor, current.scheduledStart.addingTimeInterval(current.duration))
            } else {
                current.scheduledStart = cursor
                cursor = cursor.addingTimeInterval(current.duration)
            }
        }

        undoManager.commitShift(blocks: ordered)

        // Order changed — invalidate session skips. The .onChange(venueFingerprint)
        // observer fires automatically since scheduledStart values changed.
        skippedVenuePairs.removeAll()

        if event != nil {
            Task { try? await eventRepo.save() }
        }
    }

    // MARK: - Delete

    private func deleteBlock(_ block: TimeBlockModel) {
        // Clean up any attached voice memo file before removing the block —
        // SwiftData's nullify cascade won't remove on-disk audio.
        VoiceMemoStorage.deleteFile(for: block.voiceMemoURL)

        // Capture the ID before deletion so recalculation can exclude the
        // deleted block. SwiftData marks the object for deletion lazily —
        // `sortedBlocks` still returns it from the relationship array until
        // the context is saved, which causes the cursor walk to account for
        // the deleted block's duration and shift every subsequent block forward
        // by the wrong amount.
        let deletedID = block.id
        Task {
            try? await blockRepo.delete(block)
            recalculateStartTimesAfterDelete(excluding: deletedID)
            if event != nil {
                try? await blockRepo.save()
            }
        }
    }

    private func deleteVoiceMemo(for block: TimeBlockModel) {
        VoiceMemoStorage.deleteFile(for: block.voiceMemoURL)
        block.voiceMemoURL = nil
    }

    private func recalculateStartTimesAfterDelete(excluding deletedID: UUID) {
        // Explicitly filter out the deleted block. SwiftData's lazy deletion means
        // the block is still present in `sortedBlocks` at this point, so without
        // this filter the cursor walk advances through the deleted block's duration
        // and every subsequent fluid block ends up at the wrong scheduledStart.
        let blocks = sortedBlocks.filter { $0.id != deletedID }
        guard let firstBlock = blocks.first else { return }

        let origin = event?.date ?? firstBlock.scheduledStart
        var cursor = firstBlock.isPinned ? firstBlock.scheduledStart : origin

        for block in blocks {
            if block.isPinned {
                cursor = max(cursor, block.scheduledStart.addingTimeInterval(block.duration))
            } else {
                block.scheduledStart = cursor
                // Sync originalStart so the RippleEngine's backward-shift clamp
                // reflects the block's new position, not its pre-deletion slot.
                block.originalStart = cursor
                // A deletion resolves any collision that involved the removed block.
                // Clear stale requiresReview flags — the timeline is now gap-free.
                block.requiresReview = false
                cursor = cursor.addingTimeInterval(block.duration)
            }
        }

        // Order changed — invalidate session skips.
        skippedVenuePairs.removeAll()
    }

    /// Stable fingerprint of the timeline's venue layout. Used as the trigger key
    /// for `.onChange` so the scan reactively re-runs whenever a block is added,
    /// removed, reordered, or has its venue coordinates edited.
    private var venueFingerprint: String {
        sortedBlocks
            .map { "\($0.id.uuidString):\($0.blockLatitude),\($0.blockLongitude):\(Int($0.scheduledStart.timeIntervalSinceReferenceDate))" }
            .joined(separator: "|")
    }

    /// Scans consecutive block pairs for differing venue coordinates and presents
    /// the transit block prompt for the first unhandled pair found.
    private func scanForVenueSwitches() {
        guard !isReadOnly else { return }
        // Don't stack prompts on top of an existing one.
        guard transitPromptContext == nil else { return }

        transitCheckTask?.cancel()
        transitCheckTask = Task { @MainActor in
            // Wait long enough for any other sheet's dismiss animation + SwiftUI's
            // presentation cooldown to finish. SwiftUI silently drops a sheet
            // presentation if another sheet is still mid-dismiss on the same view.
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            // Re-check after the sleep — another scan may have already presented.
            guard transitPromptContext == nil else { return }

            let blocks = sortedBlocks
            guard blocks.count >= 2 else { return }

            for index in 0..<(blocks.count - 1) {
                guard !Task.isCancelled else { return }

                let origin = blocks[index]
                let dest = blocks[index + 1]

                // Skip blocks with no location set (zero coords = not set)
                guard origin.blockLatitude != 0 || origin.blockLongitude != 0,
                      dest.blockLatitude != 0 || dest.blockLongitude != 0 else { continue }

                // Skip if venues round to the same 4dp coordinate key
                let originVenueKey = String(format: "%.4f,%.4f", origin.blockLatitude, origin.blockLongitude)
                let destVenueKey = String(format: "%.4f,%.4f", dest.blockLatitude, dest.blockLongitude)
                guard originVenueKey != destVenueKey else { continue }

                // Skip if either block is already a transit block
                guard !origin.isTransitBlock, !dest.isTransitBlock else { continue }

                // Skip if this exact pair (with these coords) was dismissed this session.
                // Pair key embeds coords so re-saving with a new location re-prompts.
                let pair = pairKey(origin: origin, destination: dest)
                guard !skippedVenuePairs.contains(pair) else { continue }

                // Fetch travel time; fall back to nil on error
                let originCoord = CLLocationCoordinate2D(latitude: origin.blockLatitude, longitude: origin.blockLongitude)
                let destCoord = CLLocationCoordinate2D(latitude: dest.blockLatitude, longitude: dest.blockLongitude)

                let minutes: Int?
                do {
                    minutes = try await travelTimeService.travelTime(from: originCoord, to: destCoord)
                } catch {
                    minutes = nil
                }

                guard !Task.isCancelled, transitPromptContext == nil else { return }
                transitPromptContext = TransitPromptContext(
                    originBlock: origin,
                    destinationBlock: dest,
                    travelMinutes: minutes
                )
                return // Only prompt for the first unhandled pair at a time
            }
        }
    }

    /// Inserts a Fluid transit block titled "Transit to [Destination]" immediately
    /// after `originBlock`. Delegates the scheduling math to
    /// ``TransitBlockInserter`` so the View stays a thin coordinator.
    private func insertTransitBlock(
        minutes: Int,
        after originBlock: TimeBlockModel,
        before destinationBlock: TimeBlockModel
    ) {
        TransitBlockInserter.insert(
            minutes: minutes,
            after: originBlock,
            before: destinationBlock,
            allBlocks: sortedBlocks,
            defaultTrack: defaultTrack,
            context: modelContext
        )
    }

    /// Stable string key for a consecutive venue-switching pair. Includes both block
    /// IDs and their current rounded coordinates so a re-save with a new location
    /// invalidates the previous skip and prompts again.
    private func pairKey(origin: TimeBlockModel, destination: TimeBlockModel) -> String {
        let originKey = String(format: "%.4f,%.4f", origin.blockLatitude, origin.blockLongitude)
        let destKey = String(format: "%.4f,%.4f", destination.blockLatitude, destination.blockLongitude)
        return "\(origin.id.uuidString)@\(originKey)→\(destination.id.uuidString)@\(destKey)"
    }
}

// MARK: - Previews

#Preview("With Blocks") {
    NavigationStack {
        TimelineBuilderView(eventID: previewEventID)
    }
    .environment(SupabaseAuthService())
    .modelContainer(previewTimelineContainer())
}

#Preview("Empty State") {
    NavigationStack {
        TimelineBuilderView(eventID: previewEmptyEventID)
    }
    .environment(SupabaseAuthService())
    .modelContainer(previewEmptyTimelineContainer())
}

private let previewEventID = UUID()
private let previewEmptyEventID = UUID()

@MainActor
private func previewTimelineContainer() -> ModelContainer {
    let container = try! PersistenceController.forTesting()
    let context = container.mainContext
    let base = Calendar.current.date(from: DateComponents(
        year: 2026, month: 6, day: 15, hour: 14
    ))!

    let event = EventModel(
        id: previewEventID, title: "Summer Wedding",
        date: base, latitude: 40.71, longitude: -74.00
    )
    context.insert(event)

    let track = TimelineTrack(name: "Main", sortOrder: 0, isDefault: true, event: event)
    context.insert(track)

    let blocks: [(String, TimeInterval, TimeInterval, Bool, String, String)] = [
        ("Ceremony",        0,    1800, true,  "#FF9500", "heart.fill"),
        ("Cocktail Hour",   1800, 3600, false, "#007AFF", "wineglass.fill"),
        ("Photo Session",   5400, 2700, false, "#AF52DE", "camera.fill"),
        ("Dinner & Toasts", 8100, 5400, true,  "#34C759", "fork.knife"),
        ("First Dance",     13500, 1200, false, "#FF2D55", "music.note"),
        ("Party",           14700, 7200, false, "#5856D6", "speaker.wave.3.fill"),
    ]
    for (title, offset, duration, pinned, color, icon) in blocks {
        let block = TimeBlockModel(
            title: title,
            scheduledStart: base.addingTimeInterval(offset),
            duration: duration,
            isPinned: pinned,
            colorTag: color,
            icon: icon
        )
        block.track = track
        context.insert(block)
    }

    return container
}

@MainActor
private func previewEmptyTimelineContainer() -> ModelContainer {
    let container = try! PersistenceController.forTesting()
    let context = container.mainContext
    let event = EventModel(
        id: previewEmptyEventID, title: "Empty Event",
        date: .now, latitude: 0, longitude: 0
    )
    context.insert(event)
    return container
}
