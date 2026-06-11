import Foundation
import Models
import Supabase
import SwiftUI

// MARK: - Protocol

/// Read/write surface for the current user's `marketplace_waitlist` row.
///
/// Online-only by design — NOT part of the SwiftData/Outbox sync stack: no
/// local mirror, no enqueue, no realtime subscription. The implementation
/// resolves `profile_id` from the active auth session and upserts on the
/// table's unique `profile_id`, so joining is idempotent: re-submitting
/// updates the one existing row.
protocol WaitlistServing: Sendable {
    /// The signed-in user's waitlist entry, or `nil` if they haven't joined.
    func currentEntry() async throws -> WaitlistEntryDTO?

    /// Joins the waitlist, or updates the existing entry (upsert on
    /// `profile_id`). `category` is dropped for planner-only signups.
    /// `customCategoryLabel` is the user-entered vendor type for the `.custom`
    /// category (ignored for built-in categories).
    @discardableResult
    func upsert(
        role: WaitlistInterestRole,
        category: VendorRole?,
        customCategoryLabel: String,
        region: String
    ) async throws -> WaitlistEntryDTO
}

// MARK: - Supabase Implementation

/// Supabase-backed ``WaitlistServing``. Stateless — holds only the
/// shared client; RLS (`marketplace_waitlist_self_all`) scopes every query to
/// the caller's own row.
struct SupabaseWaitlistService: WaitlistServing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentEntry() async throws -> WaitlistEntryDTO? {
        let profileID = try await client.auth.session.user.id
        let rows: [WaitlistEntryDTO] = try await client
            .from("marketplace_waitlist")
            .select()
            .eq("profile_id", value: profileID.uuidString)
            .execute()
            .value
        // Unique profile_id → at most one row; honour the soft-delete tombstone.
        return rows.first { $0.deletedAt == nil }
    }

    @discardableResult
    func upsert(
        role: WaitlistInterestRole,
        category: VendorRole?,
        customCategoryLabel: String,
        region: String
    ) async throws -> WaitlistEntryDTO {
        let profileID = try await client.auth.session.user.id
        let payload = Self.payload(
            profileID: profileID,
            role: role,
            category: category,
            customCategoryLabel: customCategoryLabel,
            region: region
        )
        return try await client
            .from("marketplace_waitlist")
            .upsert(payload, onConflict: "profile_id")
            .select()
            .single()
            .execute()
            .value
    }

    /// Pure payload construction, exposed internally for tests: planner-only
    /// signups never carry a category (the explicit-NULL encode then clears any
    /// stale value server-side), and the region is trimmed.
    ///
    /// A user-entered custom vendor type rides the free-text `category` column
    /// in place of the `custom` raw value (the column has no CHECK constraint),
    /// mirroring how `event_vendors.role` carries custom labels.
    static func payload(
        profileID: UUID,
        role: WaitlistInterestRole,
        category: VendorRole?,
        customCategoryLabel: String = "",
        region: String
    ) -> WaitlistEntryDTO {
        let resolvedCategory: String? = {
            guard role != .planner, let category else { return nil }
            let trimmedLabel = customCategoryLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if category == .custom && !trimmedLabel.isEmpty {
                return trimmedLabel
            }
            return category.rawValue
        }()
        return WaitlistEntryDTO(
            profileID: profileID,
            interestRole: role.rawValue,
            category: resolvedCategory,
            region: region.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - Environment

/// `nil` until the Supabase-backed service is wired at the scene level;
/// ``WaitlistSignupSheet`` treats `nil` as "waitlist unavailable".
private struct WaitlistServiceKey: EnvironmentKey {
    static let defaultValue: (any WaitlistServing)? = nil
}

extension EnvironmentValues {
    var waitlistService: (any WaitlistServing)? {
        get { self[WaitlistServiceKey.self] }
        set { self[WaitlistServiceKey.self] = newValue }
    }
}
