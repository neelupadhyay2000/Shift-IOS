import Models
import Services
import SwiftData
import SwiftUI

/// Detail for a single community template: author + verified provenance + apply
/// count, the full block list, and a gated "Use This Template" that reuses the
/// proven `UseTemplateSheet` event-creation flow. Reportable / author-blockable
/// (Apple Guideline 1.2) via the toolbar menu.
struct CommunityTemplateDetailView: View {

    let template: CommunityTemplateDTO

    @Environment(\.communityTemplateService) private var service
    @Environment(\.contentReportService) private var reportService
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(\.dismiss) private var dismiss

    /// Mirrors the roster / preview free-tier cap so applying a community template
    /// is gated identically to every other event-creation path.
    @Query private var events: [EventModel]

    @State private var isShowingCreateSheet = false
    @State private var isShowingPaywall = false
    @State private var isShowingReportDialog = false
    @State private var statusMessage: String?
    /// Bridges the new event id from `UseTemplateSheet` closing to its onDismiss.
    @State private var createdEventID: UUID?

    var body: some View {
        List {
            Section {
                header
                Text(template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                statsRow
                useButton
            }

            Section {
                ForEach(Array(template.blocks.enumerated()), id: \.offset) { _, block in
                    blockRow(block)
                }
            } header: {
                Text(String(localized: "Blocks"))
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { ProBackground() }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        isShowingReportDialog = true
                    } label: {
                        Label(String(localized: "Report Template"), systemImage: "flag")
                    }
                    Button(role: .destructive) {
                        Task { await blockAuthor() }
                    } label: {
                        Label(String(localized: "Block \(template.authorName)"), systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "Template options"))
                .disabled(reportService == nil)
            }
        }
        .confirmationDialog(
            String(localized: "Report this template?"),
            isPresented: $isShowingReportDialog,
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.displayName) { Task { await report(reason) } }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $isShowingCreateSheet, onDismiss: {
            // Navigate only after the sheet fully dismisses (mirrors TemplatePreviewView).
            if let id = createdEventID {
                deepLinkRouter.pendingDestination = .newEventTimeline(id: id)
                createdEventID = nil
            }
        }) {
            UseTemplateSheet(template: template.asTemplate, source: .community) { eventID in
                createdEventID = eventID
                // Best-effort popularity bump; never blocks navigation.
                let id = template.id
                Task { try? await service?.recordApply(templateID: id) }
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(trigger: .eventLimit)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(template.templateCategory.displayName).microLabel()
                // Authorship and provenance are separate claims. "Official" says
                // SHIFT wrote it; the seal says it came from an event actually run
                // in the app. A template can carry either, both, or neither.
                if template.isOfficial {
                    Label(String(localized: "Official"), systemImage: "rosette")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ShiftPalette.warm)
                }
                if template.sourceEventCompleted {
                    Label(String(localized: "Verified · run in Shift"), systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ShiftPalette.accent)
                }
            }
            Text(String(localized: "Shared by \(template.authorName)"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            Label {
                Text("\(template.blockCount) blocks").monospacedDigit()
            } icon: {
                Image(systemName: "rectangle.stack")
            }
            Label {
                Text(formattedDuration).monospacedDigit()
            } icon: {
                Image(systemName: "clock")
            }
            Spacer()
            // Suppressed at zero — see `CommunityTemplateDTO.hasApplies`.
            if template.hasApplies {
                Label {
                    Text("\(template.timesApplied)").monospacedDigit()
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var useButton: some View {
        Button {
            if events.count >= FreeTier.maxActiveEvents && !SubscriptionManager.shared.isProUser {
                isShowingPaywall = true
            } else {
                isShowingCreateSheet = true
            }
        } label: {
            Label(String(localized: "Use This Template"), systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(ShiftPalette.accent)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }

    private func blockRow(_ block: TemplateBlock) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: block.colorTag))
                .frame(width: 6, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(durationLabel(block.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if block.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func report(_ reason: ReportReason) async {
        guard let reportService else { return }
        do {
            try await reportService.report(
                contentType: .communityTemplate,
                contentID: template.id,
                reason: reason
            )
            statusMessage = String(localized: "Thanks — this template has been reported for review.")
        } catch {
            statusMessage = String(localized: "Couldn’t file the report. Please try again.")
        }
    }

    private func blockAuthor() async {
        guard let reportService else { return }
        do {
            try await reportService.block(profileID: template.authorID)
            statusMessage = String(localized: "You won’t see templates from this author anymore.")
            // Pop back so the now-hidden author's template leaves the screen.
            dismiss()
        } catch {
            statusMessage = String(localized: "Couldn’t block this author. Please try again.")
        }
    }

    // MARK: - Formatting

    private var formattedDuration: String {
        let total = template.blocks.map { $0.relativeStartOffset + $0.duration }.max() ?? 0
        return durationLabel(total)
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}
