import SwiftUI

/// Account type + vendor/marketplace settings (E21). An account is exclusively a
/// planner OR a vendor. Planners see an explanation + "Switch to a vendor
/// account"; vendors manage their listing/profile/availability/portfolio and can
/// "Switch to a planner account" (which hides the listing and schedules deletion
/// after a 30-day grace). Switching is the only way to cross personas.
struct VendorSettingsView: View {

    @Environment(\.marketplaceService) private var service
    @Environment(\.onboardingService) private var onboarding
    @Environment(SupabaseAuthService.self) private var authService

    @State private var vendor: VendorProfileDTO?
    @State private var isListed = false
    @State private var isLoading = true
    @State private var isUpdatingListing = false
    @State private var listingError = false

    @State private var confirmSwitchToVendor = false
    @State private var confirmSwitchToPlanner = false
    @State private var isSwitching = false
    @State private var switchError: String?

    private var isVendorAccount: Bool { authService.isVendorAccount }
    private var hasProfile: Bool { vendor != nil }
    private var graceDays: Int { onboarding?.purgeGraceDays ?? 30 }

    var body: some View {
        Form {
            if isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if isVendorAccount {
                if hasProfile {
                    listingSection
                    manageSection
                } else {
                    setupSection
                }
                switchToPlannerSection
            } else {
                switchToVendorSection
            }
            if let switchError {
                Section { Label(switchError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .scrollContentBackground(.hidden)
        .background { ProBackground() }
        .tint(ShiftPalette.accent)
        .navigationTitle(String(localized: "Account & Marketplace"))
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        // Switch → vendor
        .confirmationDialog(
            String(localized: "Switch to a vendor account?"),
            isPresented: $confirmSwitchToVendor,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Switch to Vendor")) { Task { await switchToVendor() } }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "You'll get a vendor profile and can be booked for events. As a vendor you can't request other vendors — that's a planner feature."))
        }
        // Switch → planner (with the 30-day deletion warning)
        .confirmationDialog(
            String(localized: "Switch to a planner account?"),
            isPresented: $confirmSwitchToPlanner,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Switch to Planner"), role: .destructive) { Task { await switchToPlanner() } }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Your vendor profile will be hidden right away and permanently deleted after \(graceDays) days unless you switch back. You'll be able to request vendors again."))
        }
    }

    // MARK: Vendor — listing + management

    private var listingSection: some View {
        Section {
            Toggle(isOn: Binding(get: { isListed }, set: { setListed($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Show me in the marketplace")).font(.body.weight(.medium))
                    Text(isListed
                         ? String(localized: "Planners can find and book you.")
                         : String(localized: "You're hidden from search and browse."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(isUpdatingListing)
            .accessibilityIdentifier(AccessibilityID.Settings.marketplaceListingToggle)
        } footer: {
            if listingError {
                Text(String(localized: "Couldn't update your listing. Check your connection and try again."))
                    .foregroundStyle(.red)
            }
        }
    }

    private var manageSection: some View {
        Section(String(localized: "Your vendor profile")) {
            NavigationLink { MyVendorProfileEditorView() } label: {
                Label(String(localized: "Edit vendor profile"), systemImage: "storefront")
            }
            NavigationLink { AvailabilityCalendarView() } label: {
                Label(String(localized: "Availability"), systemImage: "calendar")
            }
            NavigationLink { PortfolioEditorView() } label: {
                Label(String(localized: "Portfolio"), systemImage: "photo.on.rectangle.angled")
            }
        }
    }

    private var setupSection: some View {
        Section {
            NavigationLink { MyVendorProfileEditorView() } label: {
                Label(String(localized: "Set up your vendor profile"), systemImage: "storefront.fill")
                    .font(.body.weight(.medium))
            }
            .accessibilityIdentifier(AccessibilityID.Settings.setupVendorProfileButton)
        } footer: {
            Text(String(localized: "Create a vendor profile to get discovered in the marketplace and booked for events."))
        }
    }

    private var switchToPlannerSection: some View {
        Section {
            Button(role: .destructive) { confirmSwitchToPlanner = true } label: {
                Label(String(localized: "Switch to a planner account"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isSwitching)
            .accessibilityIdentifier(AccessibilityID.Settings.switchAccountButton)
        } header: {
            Text(String(localized: "Account type"))
        } footer: {
            Text(String(localized: "You're a vendor. Switching to a planner hides your listing and deletes it after \(graceDays) days unless you switch back."))
        }
    }

    // MARK: Planner — switch to vendor

    private var switchToVendorSection: some View {
        Section {
            Button { confirmSwitchToVendor = true } label: {
                Label(String(localized: "Switch to a vendor account"), systemImage: "storefront.fill")
                    .font(.body.weight(.medium))
            }
            .disabled(isSwitching)
            .accessibilityIdentifier(AccessibilityID.Settings.switchAccountButton)
        } header: {
            Text(String(localized: "Become a vendor"))
        } footer: {
            Text(String(localized: "You're a planner. Switch to a vendor account to list your services and get booked. You'll stop being able to request vendors while you're a vendor."))
        }
    }

    // MARK: Data

    private func load() async {
        guard let service else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        if isVendorAccount {
            vendor = (try? await service.fetchMyVendorProfile()) ?? nil
            isListed = vendor?.isListed ?? false
        } else {
            vendor = nil
        }
    }

    private func setListed(_ newValue: Bool) {
        guard let service else { return }
        let previous = isListed
        isListed = newValue
        listingError = false
        isUpdatingListing = true
        Task {
            defer { isUpdatingListing = false }
            do { try await service.setListed(newValue) }
            catch { isListed = previous; listingError = true }
        }
    }

    private func switchToVendor() async {
        guard let onboarding else { return }
        isSwitching = true; switchError = nil
        defer { isSwitching = false }
        do {
            try await onboarding.switchToVendor()
            await authService.refreshProfile()
            await load()
            Haptics.success()
            AnalyticsService.send(.accountTypeSwitched, parameters: ["to": "vendor"])
        } catch {
            switchError = String(localized: "Couldn't switch accounts. Check your connection and try again.")
        }
    }

    private func switchToPlanner() async {
        guard let onboarding else { return }
        isSwitching = true; switchError = nil
        defer { isSwitching = false }
        do {
            try await onboarding.switchToPlanner()
            await authService.refreshProfile()
            await load()
            Haptics.success()
            AnalyticsService.send(.accountTypeSwitched, parameters: ["to": "planner"])
        } catch {
            switchError = String(localized: "Couldn't switch accounts. Check your connection and try again.")
        }
    }
}
