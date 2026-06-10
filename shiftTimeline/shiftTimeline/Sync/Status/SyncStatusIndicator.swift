import SwiftUI

/// A compact sync-health glyph + label (SHIFT-664). Place it anywhere a user
/// should be able to tell, at a glance, whether sync is healthy, pending, or
/// degraded — e.g. the Settings → Diagnostics row, or a roster toolbar.
struct SyncStatusIndicator: View {
    let status: SyncStatus
    var showsLabel = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.tint)
                .imageScale(.medium)
            if showsLabel {
                Text(status.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(status.label))
    }
}

extension SyncStatus {
    /// Indicator tint: muted when healthy, accent while syncing, warm when
    /// degraded (reserves red for hard failures elsewhere).
    var tint: Color {
        switch self {
        case .healthy: return .secondary
        case .pending: return ShiftPalette.accent
        case .degraded: return ShiftPalette.warm
        }
    }
}

#Preview("States") {
    List {
        LabeledContent("Healthy") { SyncStatusIndicator(status: .healthy) }
        LabeledContent("Pending") { SyncStatusIndicator(status: .pending) }
        LabeledContent("Degraded") { SyncStatusIndicator(status: .degraded) }
    }
}
