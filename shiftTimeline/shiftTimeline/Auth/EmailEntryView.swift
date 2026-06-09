import SwiftUI

/// First step of the email-OTP sign-in flow — the email sibling of
/// ``PhoneNumberEntryView``.
///
/// Accepts an email, normalizes it, and fires an OTP request via
/// ``EmailAuthService``. On success, calls `onOTPRequested` with the normalized
/// address so the parent can swap in the OTP verification screen.
struct EmailEntryView: View {

    private let service: EmailAuthService
    /// Called with the normalized email after a successful OTP dispatch.
    let onOTPRequested: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rawEmail = ""
    @State private var isSendingOTP = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    init(service: EmailAuthService, onOTPRequested: @escaping (String) -> Void) {
        self.service = service
        self.onOTPRequested = onOTPRequested
    }

    // MARK: - Derived state

    private var normalizedEmail: String {
        EmailAuthService.normalizeEmail(rawEmail)
    }

    private var canSend: Bool {
        !isSendingOTP && EmailAuthService.isValidEmail(normalizedEmail)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 8)
                    .padding(.bottom, 32)

                emailField
                    .padding(.bottom, 12)

                sendButton

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle(String(localized: "Sign In"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .alert(String(localized: "Sign In Error"), isPresented: $showErrorAlert) {
                Button(String(localized: "OK"), role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Enter your email"))
                .font(.title2.bold())
            Text(String(localized: "We'll send a one-time code to verify your identity."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emailField: some View {
        TextField(String(localized: "Email address"), text: $rawEmail)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var sendButton: some View {
        Button {
            Task { await sendOTP() }
        } label: {
            Group {
                if isSendingOTP {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "Sending…"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(localized: "Send Code"))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSend)
    }

    // MARK: - Actions

    private func sendOTP() async {
        isSendingOTP = true
        defer { isSendingOTP = false }
        do {
            try await service.requestOTP(email: rawEmail)
            onOTPRequested(normalizedEmail)
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
}

// MARK: - Preview

#Preview {
    EmailEntryView(
        service: EmailAuthService(
            client: SupabaseClientProvider(
                supabaseURL: URL(string: "https://example.supabase.co")!,
                supabaseKey: "preview-anon-key"
            ).client
        ),
        onOTPRequested: { email in
            print("OTP requested for \(email)")
        }
    )
}
