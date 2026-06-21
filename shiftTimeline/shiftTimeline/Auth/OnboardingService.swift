import Foundation
import Supabase
import SwiftUI

// MARK: - Completion payload

/// Final write that flips `profiles.onboarded` true and stamps the account-level
/// fields. `onboarded` is always sent true; the optional identity fields use
/// encodeIfPresent so a vendor's earlier identity write (business_name/bio/avatar
/// via upsertMyVendorProfile) is never clobbered.
nonisolated struct OnboardingCompletionDTO: Encodable, Equatable {
    let displayName: String?
    let defaultRole: String?
    let bio: String?
    let accountType: String?      // "planner" | "vendor"

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case defaultRole = "default_role"
        case bio
        case accountType = "account_type"
        case onboarded
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(defaultRole, forKey: .defaultRole)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(accountType, forKey: .accountType)
        try container.encode(true, forKey: .onboarded)
    }
}

/// Vendor listing schedule update for account switching: hides + schedules a
/// purge (switch → planner) or cancels it (switch → vendor). purge_after encodes
/// as explicit null to cancel; is_listed is omitted when unchanged.
nonisolated struct VendorListingScheduleDTO: Encodable, Equatable {
    let purgeAfter: String?       // nil → explicit NULL (cancel deletion)
    let isListed: Bool?           // nil → omit

    enum CodingKeys: String, CodingKey {
        case purgeAfter = "purge_after"
        case isListed = "is_listed"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(purgeAfter, forKey: .purgeAfter)   // nil → null
        try container.encodeIfPresent(isListed, forKey: .isListed)
    }
}

// MARK: - Protocol

/// Forced profile onboarding (E19). Writes the chosen profile and flips
/// `profiles.onboarded` true. The caller refreshes the auth profile afterwards so
/// the gate dismisses.
protocol OnboardingProviding: Sendable {
    /// Planner: name + an optional short focus line (stored as bio). Sets
    /// default_role = "planner" and onboarded = true.
    func completePlanner(displayName: String, focus: String?) async throws

    /// Vendor: writes the full marketplace profile (identity + vendor_profiles),
    /// then sets default_role to the chosen category and onboarded = true.
    func completeVendor(_ input: VendorProfileInput) async throws

    /// Switch the account to vendor (planner → vendor). Cancels any pending
    /// deletion on a previously-hidden vendor profile. The caller then sets up a
    /// vendor profile if none exists.
    func switchToVendor() async throws

    /// Switch the account to planner (vendor → planner). Hides the vendor listing
    /// and schedules it for permanent deletion after a 30-day grace.
    func switchToPlanner() async throws

    /// Days of grace before a hidden vendor profile is permanently deleted.
    var purgeGraceDays: Int { get }
}

// MARK: - Supabase implementation

@MainActor
struct SupabaseOnboardingService: OnboardingProviding {
    private let client: SupabaseClient
    private let marketplace: any MarketplaceProviding

    init(client: SupabaseClient, marketplace: any MarketplaceProviding) {
        self.client = client
        self.marketplace = marketplace
    }

    let purgeGraceDays = 30

    func completePlanner(displayName: String, focus: String?) async throws {
        let uid = try await client.auth.session.user.id
        let payload = OnboardingCompletionDTO(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            defaultRole: "planner",
            bio: focus?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            accountType: "planner"
        )
        try await client.from("profiles").update(payload).eq("id", value: uid.uuidString).execute()
    }

    func completeVendor(_ input: VendorProfileInput) async throws {
        // 1) Identity (profiles reserved columns) + vendor_profiles row.
        try await marketplace.upsertMyVendorProfile(input)

        // 2) Account-level completion: default_role = chosen category, onboarded.
        //    display_name falls back to the business name so the app always has a
        //    name to show. bio is omitted here (already written in step 1).
        let uid = try await client.auth.session.user.id
        let category = SupabaseMarketplaceService.resolvedCategory(input.category, customLabel: input.customCategoryLabel)
        let payload = OnboardingCompletionDTO(
            displayName: input.businessName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            defaultRole: category,
            bio: nil,
            accountType: "vendor"
        )
        try await client.from("profiles").update(payload).eq("id", value: uid.uuidString).execute()
    }

    func switchToVendor() async throws {
        let uid = try await client.auth.session.user.id
        try await client.from("profiles")
            .update(["account_type": "vendor"])
            .eq("id", value: uid.uuidString)
            .execute()
        // Cancel any pending deletion on a previously-hidden vendor profile.
        try await client.from("vendor_profiles")
            .update(VendorListingScheduleDTO(purgeAfter: nil, isListed: nil))
            .eq("profile_id", value: uid.uuidString)
            .execute()
    }

    func switchToPlanner() async throws {
        let uid = try await client.auth.session.user.id
        try await client.from("profiles")
            .update(["account_type": "planner"])
            .eq("id", value: uid.uuidString)
            .execute()
        // Hide the vendor listing and start the 30-day deletion grace.
        let purgeAt = Date().addingTimeInterval(TimeInterval(purgeGraceDays * 24 * 60 * 60))
        try await client.from("vendor_profiles")
            .update(VendorListingScheduleDTO(purgeAfter: SupabaseTimestamp.string(from: purgeAt), isListed: false))
            .eq("profile_id", value: uid.uuidString)
            .is("deleted_at", value: nil)
            .execute()
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}

// MARK: - Environment

private struct OnboardingServiceKey: EnvironmentKey {
    static let defaultValue: (any OnboardingProviding)? = nil
}

extension EnvironmentValues {
    var onboardingService: (any OnboardingProviding)? {
        get { self[OnboardingServiceKey.self] }
        set { self[OnboardingServiceKey.self] = newValue }
    }
}
