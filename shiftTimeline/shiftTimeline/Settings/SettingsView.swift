import SwiftUI
import StoreKit
import TipKit
import Services

/// Centralized `UserDefaults` keys exposed to user-facing preferences. Keep all `@AppStorage`
/// keys here so a typo can't silently disconnect the slider/toggle from its consumer.
enum SettingsDefaultsKey {
    static let notificationThresholdMinutes = "notificationThresholdMinutes"
}

struct SettingsView: View {

    @State private var isRestoring = false
    @State private var showNoRestoreAlert = false
    @State private var showRestoreErrorAlert = false
    @State private var isShowingPaywall = false
    @State private var isManagingSubscriptions = false
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
            notificationsSection
            aboutSection
            diagnosticsSection
            #if DEBUG
            debugSection
            #endif
        }
        .navigationTitle(String(localized: "Settings"))
        .navigationBarTitleDisplayMode(.large)
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
            Button(String(localized: "OK"), role: .cancel) { }
        } message: {
            Text(String(localized: "We couldn't find any active purchases for this Apple ID. If you believe this is an error, contact support."))
        }
        .alert(String(localized: "Restore Failed"), isPresented: $showRestoreErrorAlert) {
            Button(String(localized: "OK"), role: .cancel) { }
        } message: {
            Text(String(localized: "Restore failed. Please check your connection and try again."))
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
            LabeledContent(String(localized: "Subscription")) {
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

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            LabeledContent(String(localized: "Notify me when shift exceeds:")) {
                Text(String(localized: "\(Int(thresholdMinutes)) min"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $thresholdMinutes, in: 1...60, step: 1) {
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

    var id: Self { self }

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
