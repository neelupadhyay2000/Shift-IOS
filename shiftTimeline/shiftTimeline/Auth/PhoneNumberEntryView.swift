import SwiftUI

/// First step of the phone-OTP sign-in flow.
///
/// Accepts a raw phone number, normalizes it to E.164, and fires an OTP request
/// via `PhoneAuthService`. On success, calls `onOTPRequested` with the normalized
/// number so the parent can swap in the OTP verification screen.
struct PhoneNumberEntryView: View {

    private let service: PhoneAuthService
    /// Called with the normalized E.164 phone number after a successful OTP dispatch.
    let onOTPRequested: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rawPhone = ""
    @State private var isSendingOTP = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    init(service: PhoneAuthService, onOTPRequested: @escaping (String) -> Void) {
        self.service = service
        self.onOTPRequested = onOTPRequested
    }

    // MARK: - Derived state

    private var normalizedPhone: String {
        PhoneAuthService.normalizePhone(rawPhone)
    }

    private var canSend: Bool {
        !isSendingOTP && PhoneAuthService.isValidE164(normalizedPhone)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 8)
                    .padding(.bottom, 32)

                phoneField
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
            Text(String(localized: "Enter your number"))
                .font(.title2.bold())
            Text(String(localized: "We'll send a one-time code to verify your identity."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var phoneField: some View {
        TextField(String(localized: "Phone number"), text: $rawPhone)
            .keyboardType(.phonePad)
            .textContentType(.telephoneNumber)
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
            try await service.requestOTP(phone: rawPhone)
            onOTPRequested(normalizedPhone)
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
}

// MARK: - Preview

#Preview {
    PhoneNumberEntryView(
        service: PhoneAuthService(
            client: SupabaseClientProvider(
                supabaseURL: URL(string: "https://example.supabase.co")!,
                supabaseKey: "preview-anon-key"
            ).client
        ),
        onOTPRequested: { phone in
            print("OTP requested for \(phone)")
        }
    )
}
