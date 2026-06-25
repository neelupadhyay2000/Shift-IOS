import Services
import Supabase
import SwiftUI
import TipKit

/// Centralized `UserDefaults` keys exposed to user-facing preferences. Keep all `@AppStorage`
/// keys here so a typo can't silently disconnect the slider/toggle from its consumer.
enum SettingsDefaultsKey {
    static let notificationThresholdMinutes = "notificationThresholdMinutes"
}

/// Main settings page — kept deliberately sparse: one tappable account row
/// (identity, email, and subscription live in ``AccountView``), notification
/// preferences, and About.
struct SettingsView: View {
    /// Hosted help / support page opened from the About section.
    private static let supportURL = URL(string: "https://support.shifttimeline.app")

    @Environment(SupabaseAuthService.self) private var authService
    @Environment(\.openURL) private var openURL

    @AppStorage(SettingsDefaultsKey.notificationThresholdMinutes) private var thresholdMinutes: Double = 10
    @AppStorage(AppearancePreference.defaultsKey) private var appearanceRawValue = AppearancePreference.system.rawValue

    @State private var isShowingReport = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "Version \(version)"
    }

    var body: some View {
        Form {
            accountSection
            marketplaceSection
            vendorTeamsSection
            appearanceSection
            notificationsSection
            aboutSection
            #if DEBUG
                debugSection
            #endif
        }
        .scrollContentBackground(.hidden)
        .background { ProBackground() }
        .tint(ShiftPalette.accent)
        .navigationTitle(String(localized: "Settings"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isShowingReport) {
            ReportConcernSheet()
        }
    }

    // MARK: - Account (single row → AccountView)

    private var accountSection: some View {
        Section {
            NavigationLink {
                AccountView()
            } label: {
                accountRow
            }
            .accessibilityLabel(String(localized: "Account, \(accountPrimaryLabel)"))
            .accessibilityHint(String(localized: "Shows your profile and subscription"))
        }
    }

    private var accountRow: some View {
        HStack(spacing: 16) {
            AccountAvatarView(
                initials: AccountIdentity.initials(
                    name: authService.currentProfile?.displayName,
                    email: authService.currentUser?.email
                ),
                size: 60
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(accountPrimaryLabel)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(accountSecondaryLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if authService.isAuthenticated {
                    accountTypeChip
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// Small persona badge (Facebook/LinkedIn-style) under the name.
    private var accountTypeChip: some View {
        let isVendor = authService.isVendorAccount
        return Label(
            isVendor ? String(localized: "Vendor") : String(localized: "Planner"),
            systemImage: isVendor ? "storefront.fill" : "calendar"
        )
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(ShiftPalette.accent)
        .background(ShiftPalette.soft(ShiftPalette.accent), in: Capsule())
    }

    /// A standard settings row: a soft-indigo icon tile + title (+ optional
    /// trailing value), matching the reference. The enclosing NavigationLink /
    /// Picker supplies the chevron.
    private func settingsRow(icon: String, title: String, value: String? = nil) -> some View {
        HStack(spacing: 14) {
            ShiftIconTile(systemImage: icon, size: 32)
            Text(title)
            if let value {
                Spacer(minLength: 8)
                Text(value).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    /// Primary line: display name when known, else the signed-in contact,
    /// else a generic "Account".
    private var accountPrimaryLabel: String {
        AccountIdentity.nonEmpty(authService.currentProfile?.displayName)
            ?? AccountIdentity.nonEmpty(authService.currentUser?.email)
            ?? AccountIdentity.nonEmpty(authService.currentUser?.phone)
            ?? String(localized: "Account")
    }

    /// Secondary line: the contact when signed in, else a sign-in hint.
    private var accountSecondaryLabel: String {
        guard authService.isAuthenticated else {
            return String(localized: "Sign in & subscription")
        }
        if AccountIdentity.nonEmpty(authService.currentProfile?.displayName) != nil {
            return AccountIdentity.nonEmpty(authService.currentUser?.email)
                ?? AccountIdentity.nonEmpty(authService.currentUser?.phone)
                ?? String(localized: "Signed in")
        }
        return String(localized: "Signed in")
    }

    // MARK: - Vendor & Marketplace

    private var marketplaceSection: some View {
        Section {
            NavigationLink {
                VendorSettingsView()
            } label: {
                settingsRow(icon: "storefront.fill", title: String(localized: "Account & Marketplace"))
            }
            .accessibilityIdentifier(AccessibilityID.Settings.vendorMarketplaceRow)
            .accessibilityHint(String(localized: "Your account type and marketplace listing"))
        } footer: {
            Text(String(localized: "Choose whether you're a planner or a vendor, and manage your marketplace listing."))
        }
    }

    // MARK: - Vendor Teams

    private var vendorTeamsSection: some View {
        Section {
            NavigationLink {
                VendorTeamsView()
            } label: {
                settingsRow(icon: "person.3.fill", title: String(localized: "Vendor Teams"))
            }
            .accessibilityHint(String(localized: "Manage reusable groups of vendors"))
        } footer: {
            Text(String(localized: "Save the crews you work with regularly, then add them to any event in one tap."))
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearanceRawValue) {
                ForEach(AppearancePreference.allCases) { preference in
                    Text(preference.label).tag(preference.rawValue)
                }
            } label: {
                settingsRow(icon: "paintpalette.fill", title: String(localized: "Appearance"))
            }
            .pickerStyle(.navigationLink)
        } footer: {
            Text(String(localized: "System follows your device setting."))
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
            Slider(value: $thresholdMinutes, in: 1 ... 60, step: 1) {
                Text(String(localized: "Threshold"))
            } minimumValueLabel: {
                Text("1").font(.caption2)
            } maximumValueLabel: {
                Text("60").font(.caption2)
            }
        } header: {
            Text(String(localized: "Notifications"))
        } footer: {
            Text(String(localized: "Smaller shifts will sync silently. You'll be notified only when the shift exceeds this threshold."))
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section(String(localized: "About")) {
            LabeledContent(String(localized: "Version")) {
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            if let url = Self.supportURL {
                Link(destination: url) {
                    Label(String(localized: "Help & Support"), systemImage: "questionmark.circle")
                }
                .foregroundStyle(ShiftPalette.accent)
            }
            Button(String(localized: "Privacy Policy")) {
                if let url = LegalContent.privacyPolicyURL { openURL(url) }
            }
            .foregroundStyle(ShiftPalette.accent)
            Button(String(localized: "Terms of Service")) {
                if let url = LegalContent.termsOfServiceURL { openURL(url) }
            }
            .foregroundStyle(ShiftPalette.accent)
            Button {
                isShowingReport = true
            } label: {
                Label(String(localized: "Report a Concern"), systemImage: "exclamationmark.bubble")
            }
            .foregroundStyle(ShiftPalette.accent)
        }
    }

    // MARK: - Debug (only in DEBUG builds)

    #if DEBUG
        private var debugSection: some View {
            Section(String(localized: "Developer")) {
                NavigationLink {
                    SyncDiagnosticsView()
                } label: {
                    Label(String(localized: "Sync Diagnostics"), systemImage: "stethoscope")
                }
                Button(String(localized: "Reset Tips")) {
                    try? Tips.resetDatastore()
                }
                .foregroundStyle(.red)
            }
        }
    #endif
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(SupabaseAuthService())
}
