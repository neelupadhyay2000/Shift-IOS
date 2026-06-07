import Services
import StoreKit
import Supabase
import SwiftUI
import TipKit

/// Centralized `UserDefaults` keys exposed to user-facing preferences. Keep all `@AppStorage`
/// keys here so a typo can't silently disconnect the slider/toggle from its consumer.
enum SettingsDefaultsKey {
    static let notificationThresholdMinutes = "notificationThresholdMinutes"
}

struct SettingsView: View {
    @Environment(SupabaseAuthService.self) private var authService

    @State private var isRestoring = false
    @State private var showNoRestoreAlert = false
    @State private var showRestoreErrorAlert = false
    @State private var isShowingPaywall = false
    @State private var isManagingSubscriptions = false
    @State private var isShowingSignIn = false
    @State private var isEditingName = false
    @State private var nameDraft = ""
    @State private var legalSheet: LegalSheet?

    @AppStorage(SettingsDefaultsKey.notificationThresholdMinutes) private var thresholdMinutes: Double = 10

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        Form {
            accountSection
            subscriptionSection
            notificationsSection
            aboutSection
            diagnosticsSection
            #if DEBUG
                debugSection
            #endif
        }
        .navigationTitle(String(localized: "Settings"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isShowingSignIn) {
            SignInView()
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(trigger: .settings)
        }
        .sheet(item: $legalSheet) { sheet in
            NavigationStack {
                LegalDocumentView(document: sheet.document)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done")) { legalSheet = nil }
                        }
                    }
            }
        }
        .manageSubscriptionsSheet(isPresented: $isManagingSubscriptions)
        .alert(String(localized: "No Purchases Found"), isPresented: $showNoRestoreAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "We couldn't find any active purchases for this Apple ID. If you believe this is an error, contact support."))
        }
        .alert(String(localized: "Restore Failed"), isPresented: $showRestoreErrorAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "Restore failed. Please check your connection and try again."))
        }
        .alert(String(localized: "Your Name"), isPresented: $isEditingName) {
            TextField(String(localized: "Name"), text: $nameDraft)
                .textInputAutocapitalization(.words)
            Button(String(localized: "Save")) {
                Task { await saveName() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This is the name vendors and collaborators see."))
        }
    }

    // MARK: - Account

    private var subscriptionStatusLabel: String {
        let sm = SubscriptionManager.shared
        guard sm.isProUser else { return String(localized: "Free Plan") }
        if sm.isLifetimePro { return String(localized: "SHIFT Pro — Lifetime") }
        if let renewal = sm.renewalDate {
            let formatted = renewal.formatted(.dateTime.month(.abbreviated).day().year())
            return String(localized: "SHIFT Pro — renews \(formatted)")
        }
        return String(localized: "SHIFT Pro — Active")
    }

    private var accountSection: some View {
        Section(String(localized: "Account")) {
            if authService.isAuthenticated {
                profileHeader
                Button(String(localized: "Sign Out"), role: .destructive) {
                    Task { try? await authService.signOut() }
                }
            } else {
                Button(String(localized: "Sign In")) {
                    isShowingSignIn = true
                }
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// Identity row: avatar + name with a contact line beneath. Tap to edit the
    /// display name (the name vendors/collaborators see).
    private var profileHeader: some View {
        Button {
            nameDraft = nonEmpty(authService.currentProfile?.displayName) ?? ""
            isEditingName = true
        } label: {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountPrimaryLabel)
                        .font(.headline)
                        .lineLimit(1)
                    Text(accountSecondaryLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Edit your name"))
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
            if let initials = accountInitials {
                Text(initials)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 46, height: 46)
    }

    private var subscriptionSection: some View {
        Section(String(localized: "Subscription")) {
            LabeledContent(String(localized: "Plan")) {
                Text(subscriptionStatusLabel)
                    .foregroundStyle(SubscriptionManager.shared.isProUser ? .primary : .secondary)
            }

            if !SubscriptionManager.shared.isProUser {
                Button(String(localized: "Upgrade to Pro")) {
                    isShowingPaywall = true
                }
                .foregroundStyle(Color.accentColor)
            } else if !SubscriptionManager.shared.isLifetimePro {
                Button(String(localized: "Manage Subscription")) {
                    isManagingSubscriptions = true
                }
                .foregroundStyle(Color.accentColor)
            }

            Button {
                Task { await restore() }
            } label: {
                if isRestoring {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "Restoring…"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(localized: "Restore Purchases"))
                }
            }
            .disabled(isRestoring)
        }
    }

    // MARK: - Account identity helpers

    /// Primary line: display name when known, else the contact used to sign in.
    private var accountPrimaryLabel: String {
        nonEmpty(authService.currentProfile?.displayName)
            ?? nonEmpty(authService.currentUser?.email)
            ?? nonEmpty(authService.currentUser?.phone)
            ?? String(localized: "Your Account")
    }

    /// Secondary line: the contact email/phone when the name is the primary line,
    /// otherwise a generic provider hint.
    private var accountSecondaryLabel: String {
        if nonEmpty(authService.currentProfile?.displayName) != nil {
            return nonEmpty(authService.currentUser?.email)
                ?? nonEmpty(authService.currentUser?.phone)
                ?? String(localized: "Signed in")
        }
        return String(localized: "Signed in")
    }

    /// Up to two uppercase initials from the name, else the first letter of the email.
    private var accountInitials: String? {
        if let name = nonEmpty(authService.currentProfile?.displayName) {
            let initials = name.split(separator: " ").prefix(2)
                .compactMap(\.first)
                .map(String.init)
                .joined()
            return initials.isEmpty ? nil : initials.uppercased()
        }
        if let email = nonEmpty(authService.currentUser?.email), let first = email.first {
            return String(first).uppercased()
        }
        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            LabeledContent(String(localized: "Notify me when shift exceeds:")) {
                Text(String(localized: "\(Int(thresholdMinutes)) min"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $thresholdMinutes, in: 1 ... 60, step: 1) {
                Text(String(localized: "Threshold"))
            } minimumValueLabel: {
                Text("1").font(.caption2)
            } maximumValueLabel: {
                Text("60").font(.caption2)
            }
            Text(String(localized: "Smaller shifts will sync silently. You'll be notified only when the shift exceeds this threshold."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "Notifications"))
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section(String(localized: "About")) {
            LabeledContent(String(localized: "Version")) {
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            Button(String(localized: "Privacy Policy")) {
                legalSheet = .privacy
            }
            .foregroundStyle(Color.accentColor)
            Button(String(localized: "Terms of Service")) {
                legalSheet = .terms
            }
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Diagnostics (Release-visible — used to debug iCloud sharing on TestFlight)

    private var diagnosticsSection: some View {
        Section {
            NavigationLink {
                SyncDiagnosticsView()
            } label: {
                LabeledContent(String(localized: "Sync Diagnostics")) {
                    Image(systemName: "stethoscope")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(String(localized: "Diagnostics"))
        } footer: {
            Text(String(localized: "Tools for troubleshooting iCloud sharing and sync. Tap Share in the top-right to export the log."))
        }
    }

    // MARK: - Debug (only in DEBUG builds)

    #if DEBUG
        private var debugSection: some View {
            Section(String(localized: "Developer")) {
                Button(String(localized: "Reset Tips")) {
                    try? Tips.resetDatastore()
                }
                .foregroundStyle(.red)
            }
        }
    #endif

    // MARK: - Actions

    /// Writes the edited display name to `profiles.display_name` and refreshes
    /// `currentProfile` so the header updates. No-ops on an empty value — the
    /// nil-omitting DTO encode can't null out an already-stored name anyway.
    private func saveName() async {
        guard let user = authService.currentUser else { return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        await authService.upsertProfile(from: user, displayName: trimmed)
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await SubscriptionManager.shared.restore()
            if !SubscriptionManager.shared.isProUser {
                showNoRestoreAlert = true
            }
        } catch {
            showRestoreErrorAlert = true
        }
    }
}

// MARK: - Supporting types

/// Identifies which legal document to present in the sheet. `id` is `self` so it
/// can drive `.sheet(item:)` directly.
private enum LegalSheet: Identifiable {
    case privacy
    case terms

    var id: Self {
        self
    }

    var document: LegalDocument {
        switch self {
        case .privacy: LegalContent.privacyPolicy
        case .terms: LegalContent.termsOfService
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
}
