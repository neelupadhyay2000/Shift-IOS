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
        case .pending: ShiftPalette.warm
        case .accepted: ShiftPalette.live
        case .declined: ShiftPalette.neutral
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

/// Status tag for a request — uppercase, soft-tinted, small radius (matches the
/// reference's `PENDING` / `ACCEPTED` / `DECLINED` chips).
struct RequestStatusChip: View {
    let status: String

    var body: some View {
        let resolved = ServiceRequestStatus(rawValue: status)
        let color = resolved?.color ?? ShiftPalette.neutral
        Text(resolved?.displayName ?? status.capitalized)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(color)
            .background(ShiftPalette.soft(color), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
            HStack(spacing: 8) {
                if let date {
                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                }
                if date != nil, requestedBlockCount > 0 {
                    Circle().fill(.white.opacity(0.25)).frame(width: 3, height: 3)
                }
                if requestedBlockCount > 0 {
                    Text(String(localized: "\(requestedBlockCount) blocks requested"))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}
