import SwiftUI

// Shared UI for the service-request surfaces (composer / inbox / my-requests / thread).

extension ServiceRequestStatus {
    var displayName: String {
        switch self {
        case .pending: String(localized: "Pending")
        case .accepted: String(localized: "Accepted")
        case .declined: String(localized: "Declined")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    var color: Color {
        switch self {
        case .pending: ShiftPalette.accent
        case .accepted: ShiftPalette.live
        case .declined: Color.red
        case .cancelled: ShiftPalette.neutral
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "clock"
        case .accepted: "checkmark.seal.fill"
        case .declined: "xmark.circle"
        case .cancelled: "slash.circle"
        }
    }
}

/// Status pill for a request.
struct RequestStatusChip: View {
    let status: String

    var body: some View {
        let resolved = ServiceRequestStatus(rawValue: status)
        let color = resolved?.color ?? ShiftPalette.neutral
        HStack(spacing: 4) {
            Image(systemName: resolved?.systemImage ?? "circle").font(.caption2)
            Text(resolved?.displayName ?? status.capitalized).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(color)
        .background(ShiftPalette.soft(color), in: Capsule())
    }
}

/// Compact event snapshot (title + date) rendered from the request's stored
/// snapshot — works even when the viewer has no event access (vendor pre-accept).
struct RequestEventSnapshot: View {
    let title: String
    let date: Date?
    let requestedBlockCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.isEmpty ? String(localized: "Event") : title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 10) {
                if let date {
                    Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                if requestedBlockCount > 0 {
                    Label(String(localized: "\(requestedBlockCount) blocks"), systemImage: "rectangle.stack")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
