import SwiftUI
import SafariServices
import StoreKit
import Services

struct SettingsView: View {

    @State private var isRestoring = false
    @State private var showNoRestoreAlert = false
    @State private var showRestoreErrorAlert = false
    @State private var isShowingPaywall = false
    @State private var presentedURL: IdentifiableURL?

    @AppStorage("notificationThresholdMinutes") private var thresholdMinutes: Double = 10

    private static let privacyPolicyURL = URL(string: "https://shift.app/privacy")!
    private static let termsURL = URL(string: "https://shift.app/terms")!

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
        }
        .navigationTitle(String(localized: "Settings"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(trigger: .eventLimit)
        }
        .sheet(item: $presentedURL) { identifiable in
            SafariView(url: identifiable.url)
                .ignoresSafeArea()
        }
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
                    Task { await showManageSubscriptions() }
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
                presentedURL = IdentifiableURL(url: Self.privacyPolicyURL)
            }
            .foregroundStyle(Color.accentColor)
            Button(String(localized: "Terms of Service")) {
                presentedURL = IdentifiableURL(url: Self.termsURL)
            }
            .foregroundStyle(Color.accentColor)
        }
    }

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

    @MainActor
    private func showManageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }
}

// MARK: - Supporting types

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
}
