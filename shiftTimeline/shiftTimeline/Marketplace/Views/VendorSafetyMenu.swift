import SwiftUI

/// Reusable UGC-safety affordance (Apple Guideline 1.2): an overflow menu exposing
/// **Report** and **Block** for a piece of marketplace content. Drop it into a
/// toolbar or header — it owns its report sheet and block confirmation and resolves
/// `ContentReporting` from the environment, disabling itself when unavailable.
///
/// Built generically over ``ReportableContentType`` so the same control serves the
/// vendor profile today and reviews / messages when E12/E13 ship. For a vendor
/// profile, `contentID` and `subjectProfileID` are the same id; for a review or
/// message, `contentID` is the item and `subjectProfileID` is its author (who gets
/// blocked).
struct VendorSafetyMenu: View {

    /// The author/subject — the profile that gets blocked.
    let subjectProfileID: UUID
    /// Display name for the block confirmation copy.
    let subjectName: String
    /// What is being reported.
    let contentType: ReportableContentType
    /// The reported item's id (== `subjectProfileID` for a vendor profile).
    let contentID: UUID
    /// Called after a successful block so the host can dismiss/refresh.
    var onBlocked: (() -> Void)?

    @Environment(\.contentReportService) private var service

    @State private var isPresentingReport = false
    @State private var isConfirmingBlock = false
    @State private var isWorking = false

    init(
        subjectProfileID: UUID,
        subjectName: String,
        contentType: ReportableContentType = .vendorProfile,
        contentID: UUID? = nil,
        onBlocked: (() -> Void)? = nil
    ) {
        self.subjectProfileID = subjectProfileID
        self.subjectName = subjectName
        self.contentType = contentType
        self.contentID = contentID ?? subjectProfileID
        self.onBlocked = onBlocked
    }

    var body: some View {
        Menu {
            Button {
                isPresentingReport = true
            } label: {
                Label(String(localized: "Report…"), systemImage: "flag")
            }
            .accessibilityIdentifier(AccessibilityID.Safety.reportButton)

            Button(role: .destructive) {
                isConfirmingBlock = true
            } label: {
                Label(String(localized: "Block \(subjectName)"), systemImage: "hand.raised")
            }
            .accessibilityIdentifier(AccessibilityID.Safety.blockButton)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuOrder(.fixed)
        .disabled(service == nil || isWorking)
        .accessibilityLabel(String(localized: "Report or block"))
        .accessibilityIdentifier(AccessibilityID.Safety.menu)
        .confirmationDialog(
            String(localized: "Block \(subjectName)?"),
            isPresented: $isConfirmingBlock,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Block"), role: .destructive) { Task { await block() } }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "You won't see \(subjectName) in the marketplace, and they won't see you. You can unblock from Settings."))
        }
        .sheet(isPresented: $isPresentingReport) {
            ReportReasonSheet(contentType: contentType, contentID: contentID)
        }
    }

    private func block() async {
        guard let service else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.block(profileID: subjectProfileID)
            AnalyticsService.send(.marketplaceUserBlocked, parameters: [
                "content": contentType.rawValue
            ])
            onBlocked?()
        } catch {
            // Best-effort: a failed block is non-destructive; the user can retry.
        }
    }
}

// MARK: - Report reason sheet

/// Presents the report reasons and files the report. Online-only: surfaces a
/// success or error state inline, mirroring ``WaitlistSignupSheet`` phases.
struct ReportReasonSheet: View {

    let contentType: ReportableContentType
    let contentID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.contentReportService) private var service

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ReportReason.allCases) { reason in
                        Button {
                            Task { await submit(reason) }
                        } label: {
                            HStack {
                                Text(reason.displayName)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .disabled(isSubmitting || service == nil)
                    }
                } header: {
                    Text(String(localized: "Why are you reporting this?"))
                } footer: {
                    Text(String(localized: "Reports are reviewed within 24 hours. Objectionable content and the responsible account may be removed."))
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "Report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Safety.reportCancelButton)
                }
            }
            .overlay {
                if isSubmitting { ProgressView() }
            }
            .accessibilityIdentifier(AccessibilityID.Safety.reportSheet)
        }
    }

    private func submit(_ reason: ReportReason) async {
        guard let service else {
            errorMessage = String(localized: "Reporting isn't available right now. Please try again later.")
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await service.report(contentType: contentType, contentID: contentID, reason: reason)
            AnalyticsService.send(.marketplaceContentReported, parameters: [
                "content": contentType.rawValue,
                "reason": reason.rawValue
            ])
            dismiss()
        } catch {
            errorMessage = String(localized: "Couldn't send your report. Check your connection and try again.")
        }
    }
}
