import SwiftUI
import SwiftData
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

    @State private var undoManager = ShiftUndoManager()
    @State private var isShowingCreateSheet = false
    @State private var blockToInspect: TimeBlockModel?
    @State private var blockPendingDeletion: TimeBlockModel?
    @State private var isInspectorOpen = false

    // Drag reorder state (iPhone only)
    @State private var draggingBlockID: UUID?
    @State private var dragTranslation: CGFloat = 0

    // Track management
    @State private var isShowingAddTrackAlert = false
    @State private var newTrackName = ""
    @State private var trackToRename: TimelineTrack?
    @State private var renameText = ""
    @State private var trackToDelete: TimelineTrack?

    // Track filtering — nil means "All", otherwise filters to a specific track
    @State private var selectedTrackID: UUID?

    private var event: EventModel? { results.first }

    /// True when the current user does not own this event (shared read-only).
    private var isReadOnly: Bool {
        guard let event else { return false }
        return !event.isOwnedBy(CloudKitIdentity.shared.currentUserRecordName)
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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // iPhone compact: show track tab bar when multiple tracks
            if sizeClass == .compact && sortedTracks.count > 1 {
                TrackTabBar(tracks: sortedTracks, selectedTrackID: $selectedTrackID)
            }

            Group {
                if sizeClass == .compact {
                    // iPhone: single-track filtered view
                    if filteredBlocks.isEmpty {
                        emptyState
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
        .navigationTitle(event?.title ?? String(localized: "Timeline"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !isReadOnly { toolbarItems } }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateBlockSheet(eventID: eventID, trackID: selectedTrackID)
        }
        // iPhone: sheet presentation
        .sheet(item: sheetBinding) { block in
            BlockInspectorView(block: block, eventID: eventID, isInspectorMode: false, isReadOnly: isReadOnly)
                .presentationDetents([.medium, .large])
        }
        // iPad: trailing inspector panel
        .inspector(isPresented: $isInspectorOpen) {
            if let block = blockToInspect {
                BlockInspectorView(block: block, eventID: eventID, isInspectorMode: true, isReadOnly: isReadOnly)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
            }
        }
        .onChange(of: blockToInspect) { _, newValue in
            if sizeClass != .compact {
                isInspectorOpen = newValue != nil
            }
        }
        .onChange(of: isInspectorOpen) { _, isOpen in
            if !isOpen { blockToInspect = nil }
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

    /// iPhone: single-track timeline with filter tabs.
    private var timelineContent: some View {
        ScrollView {
            let currentLayout = layout
            let blocks = filteredBlocks
            let maxYMap = nextBlockYMap(for: blocks, layout: currentLayout)

            ZStack(alignment: .topLeading) {
                // Full-width guide lines at every marker
                ForEach(currentLayout.hourMarkers, id: \.self) { marker in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(height: 0.5)
                        .offset(y: currentLayout.yOffset(for: marker) - 3)
                }

                // Pinned block anchor lines
                PinnedAnchorView(pinnedBlocks: pinnedBlocks, layout: currentLayout)

                // Golden hour / sunset markers
                SunsetMarkerView(
                    goldenHourStart: event?.goldenHourStart,
                    sunsetTime: event?.sunsetTime,
                    layout: currentLayout
                )

                HStack(alignment: .top, spacing: 0) {
                    TimeRulerView(layout: currentLayout)

                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(height: currentLayout.totalHeight)

                        ForEach(blocks) { block in
                            blockCard(block, in: currentLayout, maxY: maxYMap[block.id])
                        }

                        // Drop position indicator — shown while dragging
                        if let dragID = draggingBlockID,
                           let dragBlock = blocks.first(where: { $0.id == dragID }) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                                    .cornerRadius(1)
                            }
                            .padding(.horizontal, 4)
                            .shadow(color: Color.accentColor.opacity(0.5), radius: 6)
                            .offset(y: dropIndicatorY(forDragging: dragBlock, in: blocks, layout: currentLayout))
                            .allowsHitTesting(false)
                            .animation(.easeInOut(duration: 0.08), value: dragTranslation)
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
            .padding(.trailing, 16)
        }
        .scrollIndicators(.hidden)
        .background { WarmBackground() }
    }

    /// iPad: multi-column layout with shared time ruler and side-by-side track columns.
    private var iPadMultiColumnContent: some View {
        ScrollView {
            let currentLayout = sharedLayout

            ZStack(alignment: .topLeading) {
                // Full-width hour guide lines
                ForEach(currentLayout.hourMarkers, id: \.self) { hour in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(height: 0.5)
                        .offset(y: currentLayout.yOffset(for: hour) - 3)
                }

                // Pinned block anchor lines
                PinnedAnchorView(pinnedBlocks: pinnedBlocks, layout: currentLayout)

                // Golden hour / sunset markers
                SunsetMarkerView(
                    goldenHourStart: event?.goldenHourStart,
                    sunsetTime: event?.sunsetTime,
                    layout: currentLayout
                )

                HStack(alignment: .top, spacing: 0) {
                    TimeRulerView(layout: currentLayout)

                    HStack(alignment: .top, spacing: 8) {
                        ForEach(sortedTracks) { track in
                            TrackColumnView(
                                track: track,
                                layout: currentLayout,
                                isReadOnly: isReadOnly,
                                onTapBlock: { block in blockToInspect = block },
                                onDeleteBlock: { block in
                                    if block.isPinned {
                                        blockPendingDeletion = block
                                    } else {
                                        deleteBlock(block)
                                    }
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
        .scrollIndicators(.hidden)
        .background { WarmBackground() }
    }


    private func blockCard(
        _ block: TimeBlockModel,
        in currentLayout: TimeRulerLayout,
        maxY: CGFloat? = nil
    ) -> some View {
        let yOffset = currentLayout.yOffset(for: block.scheduledStart)
        let naturalHeight = max(currentLayout.height(for: block.duration), 52)
        let gap = (maxY ?? .infinity) - yOffset
        let height = gap > 4 ? min(naturalHeight, gap - 2) : naturalHeight
        let isDragging = draggingBlockID == block.id

        return Button {
            if draggingBlockID == nil {
                blockToInspect = block
            }
        } label: {
            TimeBlockRowView(
                title: block.title,
                scheduledStart: block.scheduledStart,
                duration: block.duration,
                isPinned: block.isPinned,
                colorTag: block.colorTag,
                icon: block.icon
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.04), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .scaleEffect(isDragging ? 1.04 : 1.0)
        .opacity(isDragging ? 0.85 : 1.0)
        .zIndex(isDragging ? 100 : 0)
        .gesture(isReadOnly ? nil :
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture())
                .onChanged { value in
                    switch value {
                    case .second(true, let drag):
                        if draggingBlockID == nil {
                            draggingBlockID = block.id
                        }
                        dragTranslation = drag?.translation.height ?? 0
                    default:
                        break
                    }
                }
                .onEnded { value in
                    guard draggingBlockID == block.id else { return }
                    if case .second(true, let drag) = value, let drag {
                        let dropY = yOffset + drag.translation.height
                        reorderBlock(block, toY: dropY, in: currentLayout)
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        draggingBlockID = nil
                        dragTranslation = 0
                    }
                }
        )
        .contextMenu {
            if !isReadOnly {
                Button {
                    blockToInspect = block
                } label: {
                    Label(String(localized: "Edit"), systemImage: "pencil")
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
        .offset(y: yOffset + (isDragging ? dragTranslation : 0))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: draggingBlockID)
    }

    private func nextBlockYMap(for blocks: [TimeBlockModel], layout: TimeRulerLayout) -> [UUID: CGFloat] {
        var map = [UUID: CGFloat]()
        for index in blocks.indices where index + 1 < blocks.count {
            map[blocks[index].id] = layout.yOffset(for: blocks[index + 1].scheduledStart)
        }
        return map
    }

    /// Y position for the insertion indicator line while a block is being dragged.
    /// Places the line at the midpoint of the gap the dragged block would drop into.
    private func dropIndicatorY(
        forDragging block: TimeBlockModel,
        in blocks: [TimeBlockModel],
        layout: TimeRulerLayout
    ) -> CGFloat {
        let draggedY = layout.yOffset(for: block.scheduledStart) + dragTranslation
        let others = blocks.filter { $0.id != block.id }
        var insertIdx = others.count
        for (i, other) in others.enumerated() {
            if draggedY < layout.yOffset(for: other.scheduledStart) {
                insertIdx = i
                break
            }
        }
        if others.isEmpty { return draggedY }
        if insertIdx == 0 {
            return layout.yOffset(for: others[0].scheduledStart) - 4
        } else if insertIdx >= others.count {
            let last = others[others.count - 1]
            return layout.yOffset(for: last.scheduledStart) + max(layout.height(for: last.duration), 52) + 4
        } else {
            let prev = others[insertIdx - 1]
            let next = others[insertIdx]
            let prevBottom = layout.yOffset(for: prev.scheduledStart) + max(layout.height(for: prev.duration), 52)
            let nextTop = layout.yOffset(for: next.scheduledStart)
            return (prevBottom + nextTop) / 2
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isShowingCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(String(localized: "Add Block"))
        }

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

        // iPad: visible undo/redo toolbar buttons (touch-friendly)
        if sizeClass != .compact {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 4) {
                    Button {
                        undoManager.undo(applying: sortedBlocks)
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
                try? modelContext.save()
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
        modelContext.insert(track)
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

        modelContext.delete(track)
        trackToDelete = nil
    }

    // MARK: - Reorder

    private func reorderBlock(
        _ block: TimeBlockModel,
        toY dropY: CGFloat,
        in currentLayout: TimeRulerLayout
    ) {
        guard !block.isPinned else { return }

        var blocks = filteredBlocks
        guard blocks.count > 1 else { return }

        // Capture before-state for undo
        undoManager.recordShift(blocks: blocks)

        // Remove the dragged block from the list
        blocks.removeAll { $0.id == block.id }

        // Determine insertion index based on drop y position
        var insertionIndex = blocks.count
        for (index, other) in blocks.enumerated() {
            let otherY = currentLayout.yOffset(for: other.scheduledStart)
            if dropY < otherY {
                insertionIndex = index
                break
            }
        }

        blocks.insert(block, at: insertionIndex)

        // Recalculate scheduledStart for all fluid blocks in new order
        guard let firstBlock = blocks.first else { return }
        var cursor = firstBlock.isPinned
            ? firstBlock.scheduledStart
            : (event?.date ?? firstBlock.scheduledStart)

        for current in blocks {
            if current.isPinned {
                cursor = max(cursor, current.scheduledStart.addingTimeInterval(current.duration))
            } else {
                current.scheduledStart = cursor
                cursor = cursor.addingTimeInterval(current.duration)
            }
        }

        // Commit after-state for undo
        undoManager.commitShift(blocks: blocks)
    }

    // MARK: - Delete

    private func deleteBlock(_ block: TimeBlockModel) {
        modelContext.delete(block)
        recalculateStartTimesAfterDelete()
    }

    private func recalculateStartTimesAfterDelete() {
        let blocks = sortedBlocks
        guard let firstBlock = blocks.first else { return }

        var cursor = firstBlock.isPinned
            ? firstBlock.scheduledStart
            : (event?.date ?? firstBlock.scheduledStart)

        for block in blocks {
            if block.isPinned {
                cursor = max(cursor, block.scheduledStart.addingTimeInterval(block.duration))
            } else {
                block.scheduledStart = cursor
                cursor = cursor.addingTimeInterval(block.duration)
            }
        }
    }
}

// MARK: - Previews

#Preview("With Blocks") {
    NavigationStack {
        TimelineBuilderView(eventID: previewEventID)
    }
    .modelContainer(previewTimelineContainer())
}

#Preview("Empty State") {
    NavigationStack {
        TimelineBuilderView(eventID: previewEmptyEventID)
    }
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
