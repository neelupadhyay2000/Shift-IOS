import SwiftUI
import Services

struct SettingsView: View {

    @State private var isRestoring = false
    @State private var showNoRestoreAlert = false
    @State private var showRestoreErrorAlert = false

    var body: some View {
        Form {
            accountSection
            aboutSection
        }
        .navigationTitle(String(localized: "Settings"))
        .navigationBarTitleDisplayMode(.large)
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

    private var accountSection: some View {
        Section(String(localized: "Account")) {
            LabeledContent(String(localized: "SHIFT Pro")) {
                Text(SubscriptionManager.shared.isProUser
                     ? String(localized: "Active")
                     : String(localized: "Free"))
                    .foregroundStyle(SubscriptionManager.shared.isProUser ? Color.green : Color.secondary)
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

    // MARK: - About

    private var aboutSection: some View {
        Section {
            NavigationLink(value: SettingsDestination.about) {
                Label(String(localized: "About SHIFT"), systemImage: "info.circle")
            }
            NavigationLink(value: SettingsDestination.licences) {
                Label(String(localized: "Licences"), systemImage: "doc.text")
            }
        }
    }

    // MARK: - Restore

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await SubscriptionManager.shared.restore()
            if !SubscriptionManager.shared.isProUser {
                showNoRestoreAlert = true
            }
            // Pro: @Observable isProUser propagates automatically — no alert needed
        } catch {
            showRestoreErrorAlert = true
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
}
