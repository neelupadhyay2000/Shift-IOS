import SwiftUI
import SwiftData
import Models

/// A single vertical track column showing positioned block cards.
///
/// Used in the iPad multi-column layout. Each column shares the same
/// `TimeRulerLayout` so blocks are vertically aligned across tracks.
/// Supports drop-to-reassign: dropping a block onto this column changes
/// the block's `track` relationship to this column's track.
struct TrackColumnView: View {

    let track: TimelineTrack
    let layout: TimeRulerLayout
    let onTapBlock: (TimeBlockModel) -> Void
    let onDeleteBlock: (TimeBlockModel) -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var isDropTargeted = false

    private var sortedBlocks: [TimeBlockModel] {
        track.blocks.sorted { $0.scheduledStart < $1.scheduledStart }
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

                let maxYMap = nextBlockYMap()
                ForEach(sortedBlocks) { block in
                    columnBlockCard(block, maxY: maxYMap[block.id])
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let blockIDString = items.first,
                      let blockID = UUID(uuidString: blockIDString) else {
                    return false
                }
                return reassignBlock(id: blockID, to: track)
            } isTargeted: { targeted in
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
                    isDropTargeted ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.06),
                    lineWidth: isDropTargeted ? 2 : 0.5
                )
        )
        .scaleEffect(isDropTargeted ? 1.02 : 1.0)
    }

    // MARK: - Block Card

    private func columnBlockCard(_ block: TimeBlockModel, maxY: CGFloat? = nil) -> some View {
        let yOffset = layout.yOffset(for: block.scheduledStart)
        let naturalHeight = max(layout.height(for: block.duration), 52)
        let gap = (maxY ?? .infinity) - yOffset
        let height = gap > 4 ? min(naturalHeight, gap - 2) : naturalHeight

        return Button {
            onTapBlock(block)
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
        .draggable(block.id.uuidString)
        .contextMenu {
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
        .padding(.horizontal, 4)
        .offset(y: yOffset)
    }

    private func nextBlockYMap() -> [UUID: CGFloat] {
        let blocks = sortedBlocks
        var map = [UUID: CGFloat]()
        for index in blocks.indices where index + 1 < blocks.count {
            map[blocks[index].id] = layout.yOffset(for: blocks[index + 1].scheduledStart)
        }
        return map
    }

    // MARK: - Drag & Drop

    private func reassignBlock(id: UUID, to targetTrack: TimelineTrack) -> Bool {
        // Find the block across all tracks in the same event
        guard let event = targetTrack.event else { return false }

        let allBlocks = event.tracks.flatMap(\.blocks)
        guard let block = allBlocks.first(where: { $0.id == id }) else { return false }

        // Skip if already on this track
        guard block.track?.id != targetTrack.id else { return false }

        block.track = targetTrack
        return true
    }
}
