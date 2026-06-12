import SwiftUI

// MARK: - Passcode field

/// Masked six-digit entry styled like the OTP code field, shared by the lock
/// screen and the setup/change flows. Auto-submits at six digits.
struct PasscodeField: View {
    @Binding var code: String
    let onComplete: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        SecureField(String(localized: "Passcode"), text: $code)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 32, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .tint(SignInPalette.cta)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .signInFieldBackground()
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onChange(of: code) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(PasscodeStore.requiredLength))
                if digits != newValue { code = digits }
                if digits.count == PasscodeStore.requiredLength { onComplete(digits) }
            }
    }
}

// MARK: - Lock screen

/// Shown over everything on every app open while a passcode exists.
///
/// Face-ID-first: when enabled, the scan prompts immediately and the keypad
/// only appears if it fails or is cancelled. "Forgot passcode?" signs out —
/// identity is then re-proven with email OTP and a fresh passcode is created.
struct AppLockScreen: View {
    let appLock: AppLock
    /// Signs out to re-authenticate via OTP (the forgot-passcode escape hatch).
    let onForgotPasscode: () -> Void

    @State private var code = ""
    @State private var showKeypad = false
    @State private var wrongCode = false
    @State private var showForgotConfirm = false

    var body: some View {
        ZStack {
            SignInBrandBackground()
            VStack(spacing: 24) {
                Spacer()
                SignInStepBadge(systemImage: "lock.fill")
                Text(String(localized: "SHIFT is locked"))
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                if showKeypad {
                    PasscodeField(code: $code) { entered in
                        if !appLock.unlock(with: entered) {
                            wrongCode = true
                            code = ""
                        }
                    }
                    .padding(.horizontal, 40)
                    if wrongCode {
                        Text(String(localized: "Wrong passcode — try again."))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                } else {
                    Button {
                        Task { await attemptBiometrics() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "faceid")
                            Text(String(localized: "Unlock with Face ID"))
                        }
                    }
                    .buttonStyle(SignInPrimaryButtonStyle())
                    .padding(.horizontal, 40)
                }

                Spacer()

                Button(String(localized: "Forgot passcode?")) {
                    showForgotConfirm = true
                }
                .font(.subheadline.weight(.medium))
                .tint(SignInPalette.cta)
                .padding(.bottom, 32)
            }
        }
        .task { await attemptBiometrics() }
        .confirmationDialog(
            String(localized: "Reset passcode?"),
            isPresented: $showForgotConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Sign Out & Reset"), role: .destructive) {
                onForgotPasscode()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "You'll sign in again with an email code and create a new passcode. Events on this device are kept."))
        }
    }

    private func attemptBiometrics() async {
        guard appLock.isFaceIDEnabled else {
            showKeypad = true
            return
        }
        await appLock.unlockWithBiometrics()
        if appLock.isLocked { showKeypad = true }
    }
}

// MARK: - Passcode setup

/// Mandatory passcode creation after the first sign-in on this device —
/// also shown once to users upgrading from a pre-passcode build. Two-entry
/// confirm, then an optional Face ID offer on capable devices.
struct PasscodeSetupView: View {

    private enum Step {
        case enter
        case confirm
        case faceIDOffer
    }

    private let appLock = AppLock.shared

    @State private var step: Step = .enter
    @State private var firstEntry = ""
    @State private var code = ""
    @State private var mismatch = false

    var body: some View {
        ZStack {
            SignInBrandBackground()
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 24)
                    .padding(.bottom, 32)

                switch step {
                case .enter, .confirm:
                    PasscodeField(code: $code) { entered in
                        advance(with: entered)
                    }
                    .id(step == .confirm)
                    if mismatch {
                        Text(String(localized: "Those didn't match — start over."))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.top, 12)
                    }
                case .faceIDOffer:
                    faceIDOffer
                }

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            SignInStepBadge(systemImage: step == .faceIDOffer ? "faceid" : "lock.fill")
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var headline: String {
        switch step {
        case .enter: String(localized: "Create a passcode")
        case .confirm: String(localized: "Confirm your passcode")
        case .faceIDOffer: String(localized: "Unlock with Face ID?")
        }
    }

    private var subtitle: String {
        switch step {
        case .enter, .confirm:
            String(localized: "You'll use this 6-digit passcode to open SHIFT — no more email codes on this device.")
        case .faceIDOffer:
            String(localized: "Open SHIFT with a glance. Your passcode still works any time.")
        }
    }

    private var faceIDOffer: some View {
        VStack(spacing: 12) {
            Button {
                UserDefaults.standard.set(true, forKey: AppLock.faceIDEnabledKey)
                finish()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "faceid")
                    Text(String(localized: "Enable Face ID"))
                }
            }
            .buttonStyle(SignInPrimaryButtonStyle())

            Button(String(localized: "Not Now")) {
                finish()
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                .white.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }

    private func advance(with entered: String) {
        switch step {
        case .enter:
            firstEntry = entered
            code = ""
            mismatch = false
            step = .confirm
        case .confirm:
            guard entered == firstEntry else {
                firstEntry = ""
                code = ""
                mismatch = true
                step = .enter
                return
            }
            if AppLock.isBiometricsAvailable {
                step = .faceIDOffer
            } else {
                finish()
            }
        case .faceIDOffer:
            break
        }
    }

    /// Storing the passcode flips `appLock.hasPasscode`; the root gate
    /// observes that and swaps this view for the app.
    private func finish() {
        appLock.setPasscode(firstEntry)
    }
}

// MARK: - Change passcode

/// Settings → Change Passcode: verify the current code, then create a new
/// one with a two-entry confirm.
struct ChangePasscodeSheet: View {

    private enum Step {
        case verify
        case enter
        case confirm
    }

    @Environment(\.dismiss) private var dismiss

    private let store = PasscodeStore()

    @State private var step: Step = .verify
    @State private var code = ""
    @State private var firstEntry = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SignInBrandBackground()
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        SignInStepBadge(systemImage: "lock.rotation")
                        Text(headline)
                            .font(.title.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 32)

                    PasscodeField(code: $code) { entered in
                        advance(with: entered)
                    }
                    .id(stepIdentity)

                    if let errorText {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.top, 12)
                    }

                    Spacer()
                }
                .padding(.horizontal, 28)
            }
            .navigationTitle(String(localized: "Change Passcode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .tint(.white.opacity(0.8))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var stepIdentity: Int {
        switch step {
        case .verify: 0
        case .enter: 1
        case .confirm: 2
        }
    }

    private var headline: String {
        switch step {
        case .verify: String(localized: "Enter current passcode")
        case .enter: String(localized: "Create a passcode")
        case .confirm: String(localized: "Confirm your passcode")
        }
    }

    private func advance(with entered: String) {
        switch step {
        case .verify:
            if store.validate(entered) {
                errorText = nil
                step = .enter
            } else {
                errorText = String(localized: "Wrong passcode — try again.")
            }
            code = ""
        case .enter:
            firstEntry = entered
            errorText = nil
            code = ""
            step = .confirm
        case .confirm:
            guard entered == firstEntry else {
                firstEntry = ""
                code = ""
                errorText = String(localized: "Those didn't match — start over.")
                step = .enter
                return
            }
            store.set(entered)
            dismiss()
        }
    }
}
