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

    private var sortedBlocks: [TimeBlockModel] {
        track.blocks.sorted { $0.scheduledStart < $1.scheduledStart }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Track header
            Text(track.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)

            // Block column
            ZStack(alignment: .topLeading) {
                // Full-height background with drop target
                Color.clear
                    .frame(height: layout.totalHeight)
                    .contentShape(Rectangle())

                ForEach(sortedBlocks) { block in
                    columnBlockCard(block)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let blockIDString = items.first,
                      let blockID = UUID(uuidString: blockIDString) else {
                    return false
                }
                return reassignBlock(id: blockID, to: track)
            } isTargeted: { isTargeted in
                // Visual feedback could be added here if needed
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    // MARK: - Block Card

    private func columnBlockCard(_ block: TimeBlockModel) -> some View {
        let yOffset = layout.yOffset(for: block.scheduledStart)
        let minHeight: CGFloat = 36
        let height = max(layout.height(for: block.duration), minHeight)

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
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
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
