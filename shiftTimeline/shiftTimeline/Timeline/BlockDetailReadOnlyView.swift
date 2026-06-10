import SwiftUI
import Models
import Services

/// Read-only block detail for a vendor viewing a shared event.
///
/// Replaces the previous approach of presenting the editing `BlockInspectorView`
/// with `.disabled(true)` — which both **blocked scrolling** (SwiftUI disables
/// the whole subtree, including the scroll gesture) and showed greyed-out edit
/// controls a vendor can't use. This is a clean, scrollable, presentation-only
/// view: labelled values, playable voice memo, assigned vendors, dependencies.
///
/// Detail is scoped per SHIFT-630 via ``BlockDetailScope``: a vendor sees full
/// detail only for blocks they're assigned to; for others they get the
/// scheduling context (title, time, location) and a short notice.
///
/// Mirrors ``BlockInspectorView``'s two presentations:
/// - **sheet** (`isInspectorMode == false`): wrapped in a `NavigationStack` with a
///   Done button (iPhone).
/// - **inspector panel** (`isInspectorMode == true`): bare grouped form, the iPad
///   trailing sidebar supplies its own chrome.
struct BlockDetailReadOnlyView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseAuthService.self) private var authService

    let block: TimeBlockModel
    /// The event the block belongs to — kept for call-site symmetry with
    /// ``BlockInspectorView`` and future use (e.g. event-scoped context).
    let eventID: UUID
    let isInspectorMode: Bool

    init(block: TimeBlockModel, eventID: UUID, isInspectorMode: Bool = false) {
        self.block = block
        self.eventID = eventID
        self.isInspectorMode = isInspectorMode
    }

    private var assignedVendors: [VendorModel] {
        (block.vendors ?? []).sorted { $0.name < $1.name }
    }

    private var dependencies: [TimeBlockModel] {
        (block.dependencies ?? []).sorted { $0.scheduledStart < $1.scheduledStart }
    }

    private var hasLocation: Bool {
        !block.venueName.isEmpty || !block.venueAddress.isEmpty
    }

    /// Full detail only for blocks this vendor is assigned to (SHIFT-630).
    private var canSeeDetails: Bool {
        BlockDetailScope.showsFullDetail(
            isReadOnly: true,
            assignedProfileIDs: (block.vendors ?? []).compactMap(\.profileId),
            currentProfileID: authService.currentProfileID
        )
    }

    // MARK: - Body

    var body: some View {
        if isInspectorMode {
            detailForm
                .formStyle(.grouped)
        } else {
            NavigationStack {
                detailForm
                    .navigationTitle(String(localized: "Block Details"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done")) { dismiss() }
                                .accessibilityIdentifier(AccessibilityID.Inspector.cancelButton)
                        }
                    }
            }
        }
    }

    private var detailForm: some View {
        Form {
            overviewSection
            if hasLocation { locationSection }
            if canSeeDetails {
                if !block.notes.isEmpty { notesSection }
                voiceMemoSection
                if !assignedVendors.isEmpty { vendorsSection }
                if !dependencies.isEmpty { dependenciesSection }
            } else {
                restrictedSection
            }
        }
    }

    // MARK: - Sections

    private var overviewSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: block.icon)
                    .font(.title3)
                    .foregroundStyle(Color(hex: block.colorTag))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: block.colorTag).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.headline)
                    Text(timeRangeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            LabeledContent(String(localized: "Duration"), value: DurationFormatter.compact(seconds: block.duration))

            if block.isPinned {
                Label(String(localized: "Pinned (fixed time)"), systemImage: "pin.fill")
                    .foregroundStyle(.secondary)
            }
            if block.isOutdoor {
                Label(String(localized: "Outdoor"), systemImage: "cloud.sun")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var locationSection: some View {
        Section(String(localized: "Location")) {
            if !block.venueName.isEmpty {
                LabeledContent(String(localized: "Venue"), value: block.venueName)
            }
            if !block.venueAddress.isEmpty {
                Text(block.venueAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var notesSection: some View {
        Section(String(localized: "Notes")) {
            Text(block.notes)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var voiceMemoSection: some View {
        if block.voiceMemoURL != nil {
            Section(String(localized: "Voice Memo")) {
                if let resolved = VoiceMemoStorage.resolve(block.voiceMemoURL) {
                    // Playback-only: no delete affordance for a read-only viewer.
                    VoiceMemoPlaybackRow(url: resolved)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.slash")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(String(localized: "Voice memo not yet available on this device"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private var vendorsSection: some View {
        Section(String(localized: "Assigned Vendors")) {
            ForEach(assignedVendors) { vendor in
                VStack(alignment: .leading, spacing: 2) {
                    Text(vendor.name)
                    Text(vendor.role.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(vendor.name), \(vendor.role.rawValue.capitalized)")
            }
        }
    }

    private var dependenciesSection: some View {
        Section(String(localized: "Depends On")) {
            ForEach(dependencies) { dependency in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dependency.isPinned ? Color.red : Color.blue)
                        .frame(width: 4, height: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dependency.title)
                        Text(dependency.scheduledStart, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(dependency.title), \(dependency.scheduledStart.formatted(.dateTime.hour().minute()))")
            }
        }
    }

    private var restrictedSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(String(localized: "Full details are shared only with vendors assigned to this block."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Helpers

    private var timeRangeText: String {
        let end = block.scheduledStart.addingTimeInterval(block.duration)
        let start = block.scheduledStart.formatted(date: .abbreviated, time: .shortened)
        let endText = end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(endText)"
    }
}
