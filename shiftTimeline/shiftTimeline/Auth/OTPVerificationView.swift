import SwiftUI

/// Second step of the phone-OTP sign-in flow.
///
/// Accepts the 6-digit code sent to `phone`, verifies it with Supabase, and
/// calls `onSessionEstablished` on success. `SupabaseAuthService` is updated
/// automatically via its `authStateChanges` listener — this callback is purely for navigation.
///
/// Resend is gated behind a 60-second cooldown that starts when the view appears
/// and resets each time a new code is dispatched.
struct OTPVerificationView: View {

    private let service: PhoneAuthService
    /// The normalized E.164 phone number the OTP was sent to.
    let phone: String
    /// Called when Supabase returns a valid session. Use this to dismiss
    /// or advance the navigation stack.
    let onSessionEstablished: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(service: PhoneAuthService, phone: String, onSessionEstablished: @escaping () -> Void) {
        self.service = service
        self.phone = phone
        self.onSessionEstablished = onSessionEstablished
    }

    @State private var token = ""
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var resendSecondsRemaining = 0
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private static let resendCooldownSeconds = 60

    // MARK: - Derived state

    private var canVerify: Bool {
        PhoneAuthService.isValidOTPToken(token) && !isVerifying
    }

    private var canResend: Bool {
        resendSecondsRemaining == 0 && !isResending && !isVerifying
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 8)
                    .padding(.bottom, 32)

                codeField
                    .padding(.bottom, 20)

                verifyButton
                    .padding(.bottom, 32)

                resendSection

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle(String(localized: "Enter Code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .onAppear {
                startCooldown()
            }
            .onChange(of: token) { _, newValue in
                // Enforce 6-character limit and trigger auto-verification.
                if newValue.count > 6 {
                    token = String(newValue.prefix(6))
                } else if newValue.count == 6 && canVerify {
                    Task { await verify() }
                }
            }
            .alert(String(localized: "Verification Failed"), isPresented: $showErrorAlert) {
                Button(String(localized: "OK"), role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Check your messages"))
                .font(.title2.bold())
            Text(
                String(
                    localized: "Enter the 6-digit code sent to \(phone).",
                    comment: "Subtitle on OTP entry screen. %@ is the phone number."
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var codeField: some View {
        TextField(String(localized: "000000"), text: $token)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .font(.system(size: 36, weight: .semibold, design: .monospaced))
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var verifyButton: some View {
        Button {
            Task { await verify() }
        } label: {
            Group {
                if isVerifying {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "Verifying…"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(localized: "Verify Code"))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canVerify)
    }

    private var resendSection: some View {
        HStack {
            Spacer()
            if resendSecondsRemaining > 0 {
                Text(
                    String(
                        localized: "Resend in \(resendSecondsRemaining)s",
                        comment: "Countdown label before the user can resend the OTP."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await resend() }
                } label: {
                    if isResending {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(String(localized: "Sending…"))
                        }
                    } else {
                        Text(String(localized: "Resend Code"))
                    }
                }
                .font(.subheadline)
                .disabled(!canResend)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func verify() async {
        isVerifying = true
        defer { isVerifying = false }
        do {
            try await service.verifyOTP(phone: phone, token: token)
            onSessionEstablished()
        } catch {
            token = ""
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func resend() async {
        isResending = true
        defer { isResending = false }
        do {
            try await service.resendOTP(phone: phone)
            token = ""
            startCooldown()
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    /// Starts (or restarts) the 60-second resend cooldown.
    ///
    /// The task runs on the MainActor so it can safely decrement the
    /// `@State` property without crossing actor boundaries.
    private func startCooldown() {
        resendSecondsRemaining = Self.resendCooldownSeconds
        Task { @MainActor in
            for remaining in stride(
                from: Self.resendCooldownSeconds - 1,
                through: 0,
                by: -1
            ) {
                try? await Task.sleep(for: .seconds(1))
                resendSecondsRemaining = remaining
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OTPVerificationView(
        service: PhoneAuthService(
            client: SupabaseClientProvider(
                supabaseURL: URL(string: "https://example.supabase.co")!,
                supabaseKey: "preview-anon-key"
            ).client
        ),
        phone: "+15551234567",
        onSessionEstablished: {
            print("Session established")
        }
    )
}
