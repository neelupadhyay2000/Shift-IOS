import Services
import StoreKit
import Supabase
import SwiftUI

/// Dedicated account screen pushed from Settings: identity (name + email),
/// subscription status and management, and sign in/out. Keeps the main
/// Settings page to a single tappable account row.
struct AccountView: View {
    @Environment(SupabaseAuthService.self) private var authService

    @State private var isRestoring = false
    @State private var showNoRestoreAlert = false
    @State private var showRestoreErrorAlert = false
    @State private var isShowingPaywall = false
    @State private var isManagingSubscriptions = false
    @State private var isShowingSignIn = false
    @State private var isEditingName = false
    @State private var nameDraft = ""
    @State private var isChangingPasscode = false

    @AppStorage(AppLock.faceIDEnabledKey) private var faceIDEnabled = true
    @State private var isConfirmingDeleteAccount = false
    @State private var isDeletingAccount = false
    @State private var showDeleteAccountErrorAlert = false

    var body: some View {
        Form {
            identitySection
            subscriptionSection
            if authService.isAuthenticated {
                privacySection
            }
            if authService.isAuthenticated {
                signOutSection
                deleteAccountSection
            }
        }
        .scrollContentBackground(.hidden)
        .background { ProBackground() }
        .tint(ShiftPalette.accent)
        .navigationTitle(String(localized: "Account"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingSignIn) {
            SignInView()
        }
        .sheet(isPresented: $isChangingPasscode) {
            ChangePasscodeSheet()
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(trigger: .settings)
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
        .confirmationDialog(
            String(localized: "Delete your account?"),
            isPresented: $isConfirmingDeleteAccount,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Account"), role: .destructive) {
                Task { await deleteAccount() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This permanently deletes your account and all synced data from SHIFT's servers. It cannot be undone. Events stored on this device are kept."))
        }
        .alert(String(localized: "Couldn't Delete Account"), isPresented: $showDeleteAccountErrorAlert) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "Account deletion failed. Please check your connection and try again."))
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        Section {
            if authService.isAuthenticated {
                profileHeader
                if let email = AccountIdentity.nonEmpty(authService.currentUser?.email) {
                    LabeledContent(String(localized: "Email")) {
                        Text(email)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else if let phone = AccountIdentity.nonEmpty(authService.currentUser?.phone) {
                    LabeledContent(String(localized: "Phone")) {
                        Text(phone)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } else {
                Button(String(localized: "Sign In")) {
                    isShowingSignIn = true
                }
                .foregroundStyle(ShiftPalette.accent)
            }
        } footer: {
            if !authService.isAuthenticated {
                Text(String(localized: "Sign in to sync your events and share timelines with vendors."))
            }
        }
    }

    /// Identity row: avatar + name. Tap to edit the display name (the name
    /// vendors and collaborators see).
    private var profileHeader: some View {
        Button {
            nameDraft = AccountIdentity.nonEmpty(authService.currentProfile?.displayName) ?? ""
            isEditingName = true
        } label: {
            HStack(spacing: 14) {
                AccountAvatarView(initials: initials, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLabel)
                        .font(.headline)
                        .lineLimit(1)
                    Text(String(localized: "Tap to edit your name"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    // MARK: - Subscription

    private var subscriptionStatusLabel: String {
        let manager = SubscriptionManager.shared
        guard manager.isProUser else { return String(localized: "Free Plan") }
        if manager.isLifetimePro { return String(localized: "SHIFT Pro — Lifetime") }
        if let renewal = manager.renewalDate {
            let formatted = renewal.formatted(.dateTime.month(.abbreviated).day().year())
            return String(localized: "SHIFT Pro — renews \(formatted)")
        }
        if manager.isComped { return String(localized: "SHIFT Pro — Complimentary") }
        return String(localized: "SHIFT Pro — Active")
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
                .foregroundStyle(ShiftPalette.accent)
            } else if SubscriptionManager.shared.renewalDate != nil {
                // Only auto-renewing subscribers have anything to manage —
                // lifetime owners and comped accounts do not.
                Button(String(localized: "Manage Subscription")) {
                    isManagingSubscriptions = true
                }
                .foregroundStyle(ShiftPalette.accent)
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

    // MARK: - Privacy & Security

    private var privacySection: some View {
        Section {
            Toggle(isOn: $faceIDEnabled) {
                Label(String(localized: "Unlock with Face ID"), systemImage: "faceid")
            }
            .disabled(!AppLock.isBiometricsAvailable)
            Button {
                isChangingPasscode = true
            } label: {
                Label(String(localized: "Change Passcode"), systemImage: "lock.rotation")
            }
            .foregroundStyle(ShiftPalette.accent)
        } header: {
            Text(String(localized: "Privacy & Security"))
        } footer: {
            Text(String(localized: "SHIFT locks every time you leave the app. Unlock with Face ID or your passcode — you stay signed in."))
        }
    }

    // MARK: - Sign out

    private var signOutSection: some View {
        Section {
            Button(String(localized: "Sign Out"), role: .destructive) {
                Task { try? await authService.signOut() }
            }
        }
    }

    // MARK: - Delete account

    private var deleteAccountSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDeleteAccount = true
            } label: {
                if isDeletingAccount {
                    HStack {
                        Text(String(localized: "Deleting Account…"))
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Text(String(localized: "Delete Account"))
                }
            }
            .disabled(isDeletingAccount)
        } footer: {
            Text(String(localized: "Permanently removes your account and all synced data. Events stored on this device are kept."))
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await authService.deleteAccount()
            // .signedOut fires through authStateChanges; the root container
            // swaps to the sign-in screen on its own.
        } catch {
            showDeleteAccountErrorAlert = true
        }
    }

    // MARK: - Identity helpers

    private var primaryLabel: String {
        AccountIdentity.nonEmpty(authService.currentProfile?.displayName)
            ?? AccountIdentity.nonEmpty(authService.currentUser?.email)
            ?? AccountIdentity.nonEmpty(authService.currentUser?.phone)
            ?? String(localized: "Your Account")
    }

    private var initials: String? {
        AccountIdentity.initials(
            name: authService.currentProfile?.displayName,
            email: authService.currentUser?.email
        )
    }

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

// MARK: - Shared identity pieces

/// Initial-circle avatar shared by the Settings account row and the Account page.
struct AccountAvatarView: View {
    let initials: String?
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(ShiftPalette.soft(ShiftPalette.accent))
            if let initials {
                Text(initials)
                    .font(size > 42 ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(ShiftPalette.accent)
            } else {
                Image(systemName: "person.fill")
                    .font(size > 42 ? .title3 : .body)
                    .foregroundStyle(ShiftPalette.accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Pure helpers for deriving the displayed identity, shared by Settings + Account.
enum AccountIdentity {
    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Up to two uppercase initials from the name, else the first letter of the email.
    static func initials(name: String?, email: String?) -> String? {
        if let name = nonEmpty(name) {
            let initials = name.split(separator: " ").prefix(2)
                .compactMap(\.first)
                .map(String.init)
                .joined()
            return initials.isEmpty ? nil : initials.uppercased()
        }
        if let email = nonEmpty(email), let first = email.first {
            return String(first).uppercased()
        }
        return nil
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AccountView()
    }
    .environment(SupabaseAuthService())
}
