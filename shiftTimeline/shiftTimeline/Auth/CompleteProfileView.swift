import SwiftUI

/// Completion gate (2026-06-25): collects whatever required fields an account
/// is still missing — a name (all accounts) and/or an email (phone-signups,
/// who must add one). Shown by `RootContainerView` after onboarding whenever
/// `SupabaseAuthService.needsProfileCompletion` is true, so it both finishes a
/// new phone-signup and validates legacy accounts created before the rule.
///
/// Writes through `completeProfile`: the `profiles` mirror (the app's source of
/// truth) plus a best-effort auth-identity write so the Supabase Users table
/// fills in. On success the cached profile refreshes, the flag flips, and the
/// gate dismisses to the app.
struct CompleteProfileView: View {

    @Environment(SupabaseAuthService.self) private var authService

    @State private var name = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var missing: Set<ProfileField> {
        ProfileCompleteness.missingFields(
            name: authService.currentProfile?.displayName,
            email: authService.accountEmail
        )
    }

    private var needsName: Bool { missing.contains(.name) }
    private var needsEmail: Bool { missing.contains(.email) }

    var body: some View {
        ZStack {
            SignInBrandBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        if needsName { nameField }
                        if needsEmail { emailField }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.white)
                                .opacity(0.9)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                submitButton
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInStepBadge(systemImage: "person.text.rectangle.fill")
                .padding(.bottom, 8)
            Text(String(localized: "Finish your profile"))
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }

    private var subtitle: String {
        if needsName && needsEmail {
            String(localized: "Add your name and email so collaborators can recognize you and we can reach you.")
        } else if needsEmail {
            String(localized: """
            Add an email to your account — it keeps your account recoverable \
            and lets us reach you.
            """)
        } else {
            String(localized: "Add your name so collaborators and vendors can recognize you.")
        }
    }

    private var nameField: some View {
        field(
            label: String(localized: "Your name"),
            text: $name,
            placeholder: String(localized: "e.g. Neel Upadhyay")
        )
        .textContentType(.name)
        .accessibilityIdentifier(AccessibilityID.CompleteProfile.nameField)
    }

    private var emailField: some View {
        field(
            label: String(localized: "Email address"),
            text: $email,
            placeholder: String(localized: "you@example.com")
        )
        .keyboardType(.emailAddress)
        .textContentType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .accessibilityIdentifier(AccessibilityID.CompleteProfile.emailField)
    }

    private func field(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.5)))
                .foregroundStyle(.white)
                .tint(SignInPalette.cta)
                .padding(14)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(ShiftPalette.accent)
                } else {
                    Text(String(localized: "Save")).font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(ShiftPalette.accent)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isSaving ? 0.7 : 1)
        }
        .buttonStyle(.pressableCard)
        .disabled(isSaving)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(AccessibilityID.CompleteProfile.submitButton)
    }

    // MARK: - Action

    private func submit() async {
        // Validate the shown fields with explicit feedback — never a silently
        // dead button. Return early with a message rather than no-op.
        if needsName, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = String(localized: "Please enter your name.")
            return
        }
        if needsEmail, !EmailAuthService.isValidEmail(EmailAuthService.normalizeEmail(email)) {
            errorMessage = String(localized: "Please enter a valid email address.")
            return
        }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await authService.completeProfile(
                name: needsName ? name : nil,
                email: needsEmail ? email : nil
            )
            // completeProfile refreshes the cached profile, flipping
            // needsProfileCompletion false so the gate dismisses to the app.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Couldn't save. Check your connection and try again.")
        }
    }
}
