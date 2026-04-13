import SwiftUI
import SwiftData
import Models
import Services

/// Displays a vertical list of time blocks for a given event, sorted chronologically.
///
/// Blocks are fetched via the event's tracks relationship.
/// Shows an empty state when no blocks exist.
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

    @State private var isShowingCreateSheet = false
    @State private var blockToInspect: TimeBlockModel?
    @State private var orderedBlocks: [TimeBlockModel] = []
    @State private var blockPendingDeletion: TimeBlockModel?

    private var event: EventModel? { results.first }

    private var sortedBlocks: [TimeBlockModel] {
        guard let event else { return [] }
        return event.tracks
            .flatMap(\.blocks)
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    var body: some View {
        Group {
            if orderedBlocks.isEmpty {
                emptyState
            } else {
                blockList
            }
        }
        .navigationTitle(event?.title ?? String(localized: "Timeline"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add Block"))
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateBlockSheet(eventID: eventID)
        }
        .sheet(item: $blockToInspect) { block in
            BlockInspectorView(block: block, eventID: eventID)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: sortedBlocks.map { "\($0.id)-\($0.scheduledStart.timeIntervalSinceReferenceDate)" }) {
            orderedBlocks = sortedBlocks
        }
        .onAppear {
            orderedBlocks = sortedBlocks
        }
    }

    // MARK: - Subviews

    private var rulerLayout: TimeRulerLayout {
        .adaptive(blocks: orderedBlocks)
    }

    private var blockList: some View {
        ScrollView {
            let layout = rulerLayout

            ZStack(alignment: .topLeading) {
                // Hour ruler on the left
                TimeRulerView(layout: layout)

                // Block cards positioned by time
                ForEach(orderedBlocks) { block in
                    let yOffset = layout.yOffset(for: block.scheduledStart)
                    let height = max(layout.height(for: block.duration), 44)

                    Button {
                        blockToInspect = block
                    } label: {
                        TimeBlockRowView(
                            title: block.title,
                            scheduledStart: block.scheduledStart,
                            duration: block.duration,
                            isPinned: block.isPinned,
                            colorTag: block.colorTag
                        )
                        .frame(height: height)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    }
                    .tint(.primary)
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
                    .padding(.leading, 56)
                    .padding(.trailing, 16)
                    .offset(y: yOffset)
                }
            }
            .frame(height: layout.totalHeight)
            .padding(.vertical, 16)
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

    // MARK: - Delete

    private func deleteBlock(_ block: TimeBlockModel) {
        orderedBlocks.removeAll { $0.id == block.id }
        modelContext.delete(block)
        recalculateStartTimesAfterDelete()
    }

    /// Recalculates `scheduledStart` for fluid blocks after a deletion to close gaps.
    private func recalculateStartTimesAfterDelete() {
        guard let firstBlock = orderedBlocks.first else { return }

        var cursor = firstBlock.isPinned
            ? firstBlock.scheduledStart
            : (event?.date ?? firstBlock.scheduledStart)

        for block in orderedBlocks {
            if block.isPinned {
                cursor = max(cursor, block.scheduledStart.addingTimeInterval(block.duration))
            } else {
                block.scheduledStart = cursor
                cursor = cursor.addingTimeInterval(block.duration)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "Add your first block"), systemImage: "clock.badge.plus")
        } actions: {
            Button(String(localized: "Add Block")) {
                isShowingCreateSheet = true
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
    let base = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14))!

    let event = EventModel(id: previewEventID, title: "Summer Wedding", date: base, latitude: 40.71, longitude: -74.00)
    context.insert(event)

    let track = TimelineTrack(name: "Main", sortOrder: 0, event: event)
    context.insert(track)

    let blocks: [(String, TimeInterval, TimeInterval, Bool, String)] = [
        ("Ceremony", 0, 1800, true, "#FF5733"),
        ("Cocktail Hour", 1800, 3600, false, "#007AFF"),
        ("Dinner", 5400, 5400, true, "#34C759"),
    ]
    for (title, offset, duration, pinned, color) in blocks {
        let block = TimeBlockModel(
            title: title,
            scheduledStart: base.addingTimeInterval(offset),
            duration: duration,
            isPinned: pinned,
            colorTag: color
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
    let event = EventModel(id: previewEmptyEventID, title: "Empty Event", date: .now, latitude: 0, longitude: 0)
    context.insert(event)
    return container
}
