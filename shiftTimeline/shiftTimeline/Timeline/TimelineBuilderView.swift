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

    @State private var isShowingCreateSheet = false
    @State private var blockToInspect: TimeBlockModel?
    @State private var blockPendingDeletion: TimeBlockModel?
    @State private var isInspectorOpen = false

    private var event: EventModel? { results.first }

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
        return event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if sortedBlocks.isEmpty {
                emptyState
            } else {
                timelineContent
            }
        }
        .navigationTitle(event?.title ?? String(localized: "Timeline"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarItems }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateBlockSheet(eventID: eventID)
        }
        // iPhone: sheet presentation
        .sheet(item: sheetBinding) { block in
            BlockInspectorView(block: block, eventID: eventID, isInspectorMode: false)
                .presentationDetents([.medium, .large])
        }
        // iPad: trailing inspector panel
        .inspector(isPresented: $isInspectorOpen) {
            if let block = blockToInspect {
                BlockInspectorView(block: block, eventID: eventID, isInspectorMode: true)
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
    }

    // MARK: - Timeline Content

    private var layout: TimeRulerLayout {
        .adaptive(blocks: sortedBlocks)
    }

    private var timelineContent: some View {
        ScrollView {
            let currentLayout = layout

            HStack(alignment: .top, spacing: 0) {
                // — Left: Time ruler
                TimeRulerView(layout: currentLayout)

                // — Right: Block cards, absolutely positioned
                ZStack(alignment: .topLeading) {
                    // Invisible spacer to establish full height
                    Color.clear
                        .frame(height: currentLayout.totalHeight)

                    ForEach(sortedBlocks) { block in
                        blockCard(block, in: currentLayout)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .padding(.trailing, 16)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Block Card

    private func blockCard(
        _ block: TimeBlockModel,
        in currentLayout: TimeRulerLayout
    ) -> some View {
        let yOffset = currentLayout.yOffset(for: block.scheduledStart)
        let minHeight: CGFloat = 44
        let height = max(currentLayout.height(for: block.duration), minHeight)

        return Button {
            blockToInspect = block
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
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
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
        .padding(.leading, 8)
        .offset(y: yOffset)
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
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "Add your first block"), systemImage: "clock.badge.plus")
        } actions: {
            Button(String(localized: "Add Block")) {
                isShowingCreateSheet = true
            }
        }
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

    let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
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
