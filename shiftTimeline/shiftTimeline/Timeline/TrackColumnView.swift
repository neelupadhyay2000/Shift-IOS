import SwiftUI
import SwiftData
import Models

/// A single vertical track column showing positioned block cards.
///
/// Used in the iPad multi-column layout. Each column shares the same
/// `TimeRulerLayout` so blocks are vertically aligned across tracks.
///
/// In normal mode: blocks are system-draggable for cross-track reassignment.
/// In edit mode: blocks use `DragGesture` for intra-column reorder with a
/// live insertion indicator; cross-track system drag is disabled.
struct TrackColumnView: View {

    let track: TimelineTrack
    let layout: TimeRulerLayout
    let isReadOnly: Bool
    let isEditing: Bool
    let onTapBlock: (TimeBlockModel) -> Void
    let onDeleteBlock: (TimeBlockModel) -> Void
    /// Called when the user drops a block in a new position within this column.
    /// Receives the dragged block, the drop y-position, and the track's current ordered blocks.
    let onReorderBlock: (TimeBlockModel, CGFloat, [TimeBlockModel]) -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var isDropTargeted = false
    @State private var draggingBlockID: UUID?
    @State private var dragTranslation: CGFloat = 0

    private var sortedBlocks: [TimeBlockModel] {
        (track.blocks ?? []).sorted { $0.scheduledStart < $1.scheduledStart }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Track header
            Text(track.name)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)

            // Block column
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(height: layout.totalHeight)
                    .contentShape(Rectangle())

                let blocks = sortedBlocks
                let maxYMap = nextBlockYMap(for: blocks)
                ForEach(blocks) { block in
                    columnBlockCard(block, allBlocks: blocks, maxY: maxYMap[block.id])
                }

                // Insertion indicator — live preview of drop position while dragging
                if let dragID = draggingBlockID,
                   let dragBlock = blocks.first(where: { $0.id == dragID }) {
                    insertionIndicator
                        .offset(y: insertionIndicatorY(forDragging: dragBlock, in: blocks))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .animation(.easeInOut(duration: 0.08), value: dragTranslation)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                // Cross-track drop only active outside of edit mode
                guard !isReadOnly, !isEditing,
                      let blockIDString = items.first,
                      let blockID = UUID(uuidString: blockIDString) else {
                    return false
                }
                return reassignBlock(id: blockID, to: track)
            } isTargeted: { targeted in
                guard !isEditing else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDropTargeted = targeted
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    (isDropTargeted && !isEditing) ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.06),
                    lineWidth: (isDropTargeted && !isEditing) ? 2 : 0.5
                )
        )
        .scaleEffect((isDropTargeted && !isEditing) ? 1.02 : 1.0)
        .onChange(of: isEditing) { _, editing in
            // Clear any stale drop-target highlight when entering edit mode
            if editing { isDropTargeted = false }
        }
    }

    // MARK: - Insertion Indicator

    private var insertionIndicator: some View {
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
    }

    /// Y offset for the insertion line: snaps to the gap between the two surrounding
    /// blocks as the user drags, giving a real-time preview of the drop position.
    private func insertionIndicatorY(forDragging block: TimeBlockModel, in blocks: [TimeBlockModel]) -> CGFloat {
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

    // MARK: - Block Card

    private func columnBlockCard(_ block: TimeBlockModel, allBlocks: [TimeBlockModel], maxY: CGFloat? = nil) -> some View {
        let yOffset = layout.yOffset(for: block.scheduledStart)
        let durationHeight = layout.height(for: block.duration)
        let useCompact = durationHeight < 50
        let minHeight: CGFloat = useCompact ? 32 : 52
        let naturalHeight = max(durationHeight, minHeight)
        let height: CGFloat = {
            guard !useCompact, let maxY else { return naturalHeight }
            let gap = maxY - yOffset
            return gap > 4 ? min(naturalHeight, gap - 2) : naturalHeight
        }()
        let isDragging = draggingBlockID == block.id
        let isDraggable = isEditing && !block.isPinned && !isReadOnly

        return Button {
            guard !isEditing else { return }
            onTapBlock(block)
        } label: {
            HStack(spacing: 0) {
                // Drag handle — only visible in edit mode for fluid blocks
                if isDraggable {
                    Image(systemName: "line.3.horizontal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
                TimeBlockRowView(
                    title: block.title,
                    scheduledStart: block.scheduledStart,
                    duration: block.duration,
                    isPinned: block.isPinned,
                    colorTag: block.colorTag,
                    icon: block.icon,
                    isCompact: useCompact
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
                // Highlighted border for draggable blocks in edit mode
                if isDraggable {
                    RoundedRectangle(cornerRadius: ShiftDesign.cardRadius, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(isDragging ? 0.7 : 0.4), lineWidth: 1.5)
                        .animation(.easeInOut(duration: 0.2), value: isDragging)
                }
            }
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.04), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        // Scale and opacity animate on lift/drop — scoped to isDragging so they
        // do NOT animate dragTranslation changes (which must track the finger immediately).
        .scaleEffect(isDragging ? 1.04 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .opacity(isDragging ? 0.85 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .zIndex(isDragging ? 100 : 0)
        // In edit mode: DragGesture for intra-column reorder
        .gesture(isDraggable ?
            DragGesture(minimumDistance: 5)
                .onChanged { drag in
                    // Set block ID without animation — withAnimation here would batch
                    // draggingBlockID + dragTranslation into one animated pass, causing
                    // the offset to lag behind the finger instead of tracking it.
                    if draggingBlockID == nil {
                        draggingBlockID = block.id
                    }
                    dragTranslation = drag.translation.height
                }
                .onEnded { drag in
                    let dropY = yOffset + drag.translation.height
                    defer {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            draggingBlockID = nil
                            dragTranslation = 0
                        }
                    }
                    guard draggingBlockID == block.id else { return }
                    onReorderBlock(block, dropY, allBlocks)
                }
            : nil
        )
        // Outside edit mode: system drag for cross-column reassignment
        .modifier(ConditionalDraggable(isEnabled: !isReadOnly && !isEditing, payload: block.id.uuidString))
        .contextMenu {
            if !isReadOnly && !isEditing {
                Button {
                    onTapBlock(block)
                } label: {
                    Label(String(localized: "Edit"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDeleteBlock(block)
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
            }
        }
        .padding(.horizontal, 4)
        .offset(y: yOffset + (isDragging ? dragTranslation : 0))
    }

    private func nextBlockYMap(for blocks: [TimeBlockModel]) -> [UUID: CGFloat] {
        var map = [UUID: CGFloat]()
        for index in blocks.indices where index + 1 < blocks.count {
            map[blocks[index].id] = layout.yOffset(for: blocks[index + 1].scheduledStart)
        }
        return map
    }

    // MARK: - Cross-Column Drag & Drop

    private func reassignBlock(id: UUID, to targetTrack: TimelineTrack) -> Bool {
        guard let event = targetTrack.event else { return false }
        let allBlocks = (event.tracks ?? []).flatMap { $0.blocks ?? [] }
        guard let block = allBlocks.first(where: { $0.id == id }) else { return false }
        guard block.track?.id != targetTrack.id else { return false }
        block.track = targetTrack
        return true
    }
}

// MARK: - Conditional Draggable

/// Applies `.draggable` only when `isEnabled` is true.
/// In edit mode `isEnabled` is false so the system drag preview doesn't
/// conflict with the DragGesture-based reorder.
private struct ConditionalDraggable: ViewModifier {
    let isEnabled: Bool
    let payload: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(payload)
        } else {
            content
        }
    }
}
