import SwiftUI
import Engine
import Models

// MARK: - ShiftPreview + Identifiable (UI layer only)

extension ShiftPreview: @retroactive Identifiable {
    public var id: Int {
        // Stable identity from the preview content — sufficient for sheet presentation.
        var hasher = Hasher()
        for block in previewBlocks {
            hasher.combine(block.id)
        }
        hasher.combine(status.rawValue)
        return hasher.finalize()
    }
}

/// Shows a before/after comparison of affected blocks before committing a shift.
///
/// Presented as a sheet after the user selects a shift amount from `QuickShiftSheet`.
/// Only the "Confirm Shift" button triggers the actual RippleEngine mutation.
/// "Cancel" discards the preview with zero data changes.
struct ShiftPreviewOverlay: View {

    let preview: ShiftPreview
    let minutes: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    /// Blocks that would actually move (non-zero diff).
    private var affectedBlocks: [(block: PreviewBlock, diff: TimeInterval)] {
        preview.previewBlocks.compactMap { block in
            let diff = preview.diffs[block.id] ?? 0
            guard abs(diff) > 0.5 else { return nil }
            return (block, diff)
        }
    }

    /// Whether the preview represents an error that prevents the shift.
    private var isErrorStatus: Bool {
        switch preview.status {
        case .pinnedBlockCannotShift, .circularDependency:
            return true
        case .clean, .hasCollisions, .impossible:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                if isErrorStatus {
                    errorView
                } else if affectedBlocks.isEmpty {
                    noChangesView
                } else {
                    blockList
                }

                Spacer()
                actionButtons
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        onCancel()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title)
                .foregroundStyle(Color.accentColor)

            Text(String(localized: "Shift Preview"))
                .font(.title2.weight(.bold))

            Text(String(localized: "+\(minutes) min — \(affectedBlocks.count) blocks affected"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Block List

    private var blockList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(affectedBlocks, id: \.block.id) { item in
                    diffRow(block: item.block, diff: item.diff)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func diffRow(block: PreviewBlock, diff: TimeInterval) -> some View {
        let beforeDate = block.scheduledStart.addingTimeInterval(-diff)
        let afterDate = block.scheduledStart
        let diffMinutes = Int(diff / 60)
        let sign = diffMinutes > 0 ? "+" : ""

        return HStack(spacing: 12) {
            // Block title + pin indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if block.isPinned {
                    Text(String(localized: "Pinned"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Before → After times
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(beforeDate, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(afterDate, format: .dateTime.hour().minute())
                        .foregroundStyle(.primary)
                }
                .font(.caption.weight(.medium))

                Text(String(localized: "\(sign)\(diffMinutes) min"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(diffMinutes > 0 ? Color.orange : Color.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(statusMessage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var statusMessage: String {
        switch preview.status {
        case .pinnedBlockCannotShift:
            return String(localized: "A pinned block prevents this shift.")
        case .circularDependency:
            return String(localized: "A circular dependency prevents this shift.")
        case .clean, .hasCollisions, .impossible:
            return ""
        }
    }

    // MARK: - No Changes

    private var noChangesView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text(String(localized: "No blocks affected"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                onConfirm()
            } label: {
                Text(String(localized: "Confirm Shift"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .disabled(isErrorStatus || affectedBlocks.isEmpty)

            Button {
                onCancel()
            } label: {
                Text(String(localized: "Cancel"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }
}
