import SwiftUI
import Models

/// A single row in the timeline builder list.
///
/// The block's colour appears in exactly one place: a solid circular icon badge
/// (the Structured signature). Typography carries the rest — semibold title,
/// tabular time figures. Only the *exception* is flagged: pinned blocks get a
/// chip; fluid is the default and shows nothing.
///
/// When `isCompact` is true, renders a slim single-line variant suitable for
/// short blocks (e.g. transit blocks) that fits cleanly in ~32pt of height.
struct TimeBlockRowView: View {

    let title: String
    let scheduledStart: Date
    let duration: TimeInterval
    let isPinned: Bool
    let colorTag: String
    let icon: String
    var isCompact: Bool = false
    /// When `true`, marks this block as assigned to the current (vendor) viewer —
    /// shows an "Assigned" badge so a vendor can tell which blocks are theirs.
    var isAssignedToViewer: Bool = false

    private var accentColor: Color {
        Color(hex: colorTag)
    }

    var body: some View {
        if isCompact {
            compactBody
        } else {
            fullBody
        }
    }

    // MARK: - Full layout

    private var fullBody: some View {
        HStack(spacing: 12) {
            iconBadge(size: 38, glyphSize: 15)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(scheduledStart, format: .dateTime.hour().minute())
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(verbatim: "·")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                    Text(formattedDuration)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                // "Assigned to you" badge — only for a vendor's assigned blocks.
                if isAssignedToViewer {
                    assignedBadge
                }
                // Only the exception is flagged: pinned blocks are anchored.
                if isPinned {
                    pinnedChip
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Compact layout

    /// Slim single-line row for short blocks. ~32pt tall.
    private var compactBody: some View {
        HStack(spacing: 8) {
            iconBadge(size: 22, glyphSize: 10)

            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 4)

            if isAssignedToViewer {
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ShiftPalette.live)
                    .accessibilityHidden(true)
            }

            Text(formattedDuration)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Pieces

    /// Solid circular icon badge — the one place the block's colour lives.
    private func iconBadge(size: CGFloat, glyphSize: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: glyphSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(accentColor, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            .symbolEffect(.bounce, value: isPinned)
            .accessibilityHidden(true)
    }

    /// Quiet capsule flagging an anchored (pinned) block.
    private var pinnedChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "pin.fill")
                .font(.system(size: 8, weight: .bold))
            Text(String(localized: "Pinned"))
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.12), in: Capsule())
    }

    /// Green "Assigned" pill shown on a vendor's own blocks. Uses the short label
    /// to fit the row's trailing column.
    private var assignedBadge: some View {
        AssignedToYouBadge(text: String(localized: "Assigned"))
    }

    private var formattedDuration: String {
        DurationFormatter.compact(minutes: Int(duration) / 60)
            .replacingOccurrences(of: " min", with: "m")
    }

    /// Spoken label: "[Title], [N minutes/hours], [Fluid/Pinned], starts at [HH:MM]"
    private var accessibilityDescription: String {
        let totalMinutes = Int(duration) / 60
        let durationStr: String
        if totalMinutes < 60 {
            durationStr = "\(totalMinutes) minutes"
        } else {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            let hoursStr = h == 1 ? String(localized: "hour") : String(localized: "hours")
            durationStr = m > 0 ? "\(h) \(hoursStr) \(m) minutes" : "\(h) \(hoursStr)"
        }
        let typeStr = isPinned ? String(localized: "Pinned") : String(localized: "Fluid")
        let timeStr = scheduledStart.formatted(.dateTime.hour().minute())
        let assignedStr = isAssignedToViewer ? String(localized: ", assigned to you") : ""
        return "\(title), \(durationStr), \(typeStr), starts at \(timeStr)\(assignedStr)"
    }
}

// MARK: - Color hex initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
