import Supabase
import SwiftUI

/// Everything about the account, in one place: the name vendors see, and the two
/// credentials you can sign in with.
///
/// The asymmetry is the point. `display_name` lives only on `profiles`, so editing
/// it is a plain write. Email and phone are **sign-in credentials** held by GoTrue;
/// changing either sends a fresh one-time code that must be verified before the
/// change commits. Without that, anyone holding a live session on an unlocked phone
/// could move the account to their own address and lock the owner out permanently.
///
/// Email changes are double-confirmed (`double_confirm_changes`): a code goes to
/// the new address *and* to the current one, and both must be entered. Adding an
/// email to a phone-only account needs just one, since there is no old address to
/// notify. See ``CredentialChangeSheet``.
struct EditAccountView: View {
    @Environment(SupabaseAuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var nameDraft = ""
    @State private var isSavingName = false
    @State private var nameError: String?
    @State private var didSaveName = false

    @State private var credentialChange: CredentialKind?

    private var currentEmail: String? { AccountIdentity.nonEmpty(authService.currentUser?.email) }
    private var currentPhone: String? { AccountIdentity.nonEmpty(authService.currentUser?.phone) }

    private var savedName: String {
        AccountIdentity.nonEmpty(authService.currentProfile?.displayName) ?? ""
    }

    private var trimmedDraft: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveName: Bool {
        !trimmedDraft.isEmpty && trimmedDraft != savedName && !isSavingName
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                credentialsSection
            }
            .scrollContentBackground(.hidden)
            .background { ProBackground() }
            .tint(ShiftPalette.accent)
            .navigationTitle(String(localized: "Edit Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .sheet(item: $credentialChange) { kind in
                CredentialChangeSheet(kind: kind)
            }
            .task { nameDraft = savedName }
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        Section {
            TextField(String(localized: "Name"), text: $nameDraft)
                .textInputAutocapitalization(.words)
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit { if canSaveName { Task { await saveName() } } }

            Button {
                Task { await saveName() }
            } label: {
                HStack {
                    Text(String(localized: "Save Name"))
                    Spacer()
                    if isSavingName { ProgressView() }
                    else if didSaveName, trimmedDraft == savedName {
                        Image(systemName: "checkmark").foregroundStyle(.green)
                    }
                }
            }
            .disabled(!canSaveName)
        } header: {
            Text(String(localized: "Name"))
        } footer: {
            if let nameError {
                Text(nameError).foregroundStyle(.red)
            } else {
                Text(String(localized: "This is the name vendors and collaborators see."))
            }
        }
    }

    // MARK: - Credentials

    private var credentialsSection: some View {
        Section {
            credentialRow(
                kind: .email,
                title: String(localized: "Email"),
                value: currentEmail
            )
            credentialRow(
                kind: .phone,
                title: String(localized: "Phone"),
                value: currentPhone
            )
        } header: {
            Text(String(localized: "Sign-In"))
        } footer: {
            Text(String(localized: "You can sign in with either one. Changing a credential sends a verification code — we'll never change it without one."))
        }
    }

    private func credentialRow(kind: CredentialKind, title: String, value: String?) -> some View {
        Button {
            credentialChange = kind
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(value ?? String(localized: "Not set"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                // "Add" reads better than "Change" for a credential you don't have —
                // and it's the phone-only account's path to an email, and the
                // email-only account's path to phone sign-in.
                Text(value == nil ? String(localized: "Add") : String(localized: "Change"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ShiftPalette.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func saveName() async {
        guard canSaveName else { return }
        isSavingName = true
        nameError = nil
        didSaveName = false
        defer { isSavingName = false }
        do {
            try await authService.updateDisplayName(trimmedDraft)
            didSaveName = true
            Haptics.success()
        } catch {
            nameError = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Couldn't save your name. Check your connection and try again.")
        }
    }
}

// MARK: - Credential kind

/// Which sign-in credential is being edited. `Identifiable` so it can drive a
/// `.sheet(item:)` — the identity also forces a fresh sheet per credential.
enum CredentialKind: String, Identifiable, Hashable {
    case email
    case phone

    var id: String { rawValue }
}

// MARK: - Credential change flow

/// Two steps: type the new value, then verify the code(s).
///
/// An email change under `double_confirm_changes` produces **two** pending
/// addresses — the new one and the current one — and the change commits only after
/// both codes are entered. We drive that off the server's answer rather than a
/// local assumption: ``SupabaseAuthService/confirmEmailChange(address:token:)``
/// re-reads the user and reports whether `newEmail` is still pending. If the hosted
/// project has secure email change turned off, the first confirmation reports
/// committed and we stop early — so this works either way, without the client
/// needing to know the server's setting.
private struct CredentialChangeSheet: View {
    let kind: CredentialKind

    @Environment(SupabaseAuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    /// Addresses/numbers still awaiting a code, in the order we ask for them. The
    /// new value first — that's the inbox the user is already looking at.
    @State private var pending: [String] = []
    /// Set by the verify closure so `onSessionEstablished` knows whether the change
    /// fully committed or another leg remains.
    @State private var committed = false

    var body: some View {
        Group {
            if let destination = pending.first {
                // OTPVerificationView supplies its own NavigationStack, title and
                // Cancel — don't wrap it, or the sheet grows two nav bars. Its
                // Cancel dismisses this sheet, abandoning the change; GoTrue simply
                // lets the pending change expire unconfirmed.
                OTPVerificationView(
                    destination: destination,
                    headline: headline(for: destination),
                    verifyToken: { token in try await confirm(destination, token) },
                    resendCode: { try await send() },
                    onSessionEstablished: advance
                )
                // Fresh state (and a cleared code field) for the second leg.
                .id(destination)
            } else {
                entryNavigation
            }
        }
        // Once a code is out, a swipe-down would strand a half-confirmed change.
        .interactiveDismissDisabled(!pending.isEmpty)
    }

    private var entryNavigation: some View {
        NavigationStack {
            entryForm
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                }
        }
    }

    private var title: String {
        switch kind {
        case .email: String(localized: "Email")
        case .phone: String(localized: "Phone")
        }
    }

    private var entryForm: some View {
        Form {
            Section {
                switch kind {
                case .email:
                    TextField(String(localized: "New email address"), text: $draft)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                case .phone:
                    TextField(String(localized: "New phone number"), text: $draft)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                Button {
                    Task { await start() }
                } label: {
                    HStack {
                        Text(String(localized: "Send Code"))
                        Spacer()
                        if isSending { ProgressView() }
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else {
                    Text(footerText)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { ProBackground() }
    }

    /// Told up front, because a two-code flow is baffling when it's a surprise.
    private var footerText: String {
        switch kind {
        case .email:
            AccountIdentity.nonEmpty(authService.currentUser?.email) == nil
                ? String(localized: "We'll send a 6-digit code to confirm it's yours.")
                : String(localized: "We'll send a code to your new address and to your current one. Enter both to confirm the change.")
        case .phone:
            String(localized: "We'll text a 6-digit code to confirm it's yours. Include your country code.")
        }
    }

    private func headline(for destination: String) -> String {
        switch kind {
        case .email: String(localized: "Check \(destination)")
        case .phone: String(localized: "Check your messages")
        }
    }

    // MARK: Actions

    private func start() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await send()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Couldn't send the code. Check your connection and try again.")
        }
    }

    /// Also the resend path, so a resend re-issues every outstanding leg.
    private func send() async throws {
        switch kind {
        case .email:
            pending = try await authService.beginEmailChange(to: draft)
        case .phone:
            try await authService.beginPhoneChange(to: draft)
            pending = [PhoneAuthService.normalizePhone(draft)]
        }
    }

    private func confirm(_ destination: String, _ token: String) async throws {
        switch kind {
        case .email:
            committed = try await authService.confirmEmailChange(address: destination, token: token)
        case .phone:
            try await authService.confirmPhoneChange(phone: destination, token: token)
            committed = true
        }
    }

    private func advance() {
        if committed {
            Haptics.success()
            dismiss()
            return
        }
        // The server still reports a pending change: collect the other leg.
        pending.removeFirst()
        if pending.isEmpty { dismiss() }
    }
}
