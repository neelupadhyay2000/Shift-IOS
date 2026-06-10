import Foundation
import Models
import SwiftUI

// MARK: - Interest Role

/// Which side of the marketplace the user is signing up for. Raw values match
/// the `marketplace_waitlist.interest_role` CHECK constraint exactly
/// (`vendor` | `planner` | `both`).
enum WaitlistInterestRole: String, CaseIterable {
    case vendor
    case planner
    case both

    var displayName: String {
        switch self {
        case .vendor: String(localized: "I'm a vendor")
        case .planner: String(localized: "I'm a planner")
        case .both: String(localized: "Both")
        }
    }

    var systemImage: String {
        switch self {
        case .vendor: "storefront.fill"
        case .planner: "clipboard.fill"
        case .both: "person.2.fill"
        }
    }
}

// MARK: - DTO

/// One row of the Supabase `marketplace_waitlist` table.
///
/// Unlike `ProfileDTO`, `category` is encoded even when nil: switching from a
/// vendor signup to planner-only must clear the stale category on the server,
/// so the upsert writes an explicit NULL.
///
/// All conformance witnesses are explicitly `nonisolated` (ProfileDTO
/// convention) so the target's MainActor default isolation doesn't isolate
/// them — the Supabase SDK decodes responses off the main actor.
struct WaitlistEntryDTO: Sendable {
    let profileID: UUID
    /// `WaitlistInterestRole` rawValue.
    let interestRole: String
    /// `VendorRole` rawValue — only meaningful for vendor/both signups.
    let category: String?
    let region: String

    private enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case interestRole = "interest_role"
        case category
        case region
    }
}

// MARK: - Encodable

extension WaitlistEntryDTO: Encodable {
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(interestRole, forKey: .interestRole)
        try container.encode(category, forKey: .category) // nil → explicit NULL
        try container.encode(region, forKey: .region)
    }
}

// MARK: - Decodable

extension WaitlistEntryDTO: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try container.decode(UUID.self, forKey: .profileID)
        interestRole = try container.decode(String.self, forKey: .interestRole)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        region = try container.decode(String.self, forKey: .region)
    }
}

// MARK: - Equatable

// swiftformat:disable all
extension WaitlistEntryDTO: Equatable {
    nonisolated static func == (lhs: WaitlistEntryDTO, rhs: WaitlistEntryDTO) -> Bool {
        lhs.profileID == rhs.profileID
            && lhs.interestRole == rhs.interestRole
            && lhs.category == rhs.category
            && lhs.region == rhs.region
    }
}
// swiftformat:enable all

// MARK: - Protocol

/// Read/write surface for the current user's `marketplace_waitlist` row.
///
/// Online-only by design — no SwiftData mirror, no Outbox enqueue, no realtime.
/// The Supabase implementation (SHIFT-717) resolves `profile_id` from the
/// active auth session and upserts on the table's unique `profile_id`, so
/// joining is idempotent: re-submitting updates the one existing row.
protocol WaitlistServing: Sendable {
    /// The signed-in user's waitlist entry, or `nil` if they haven't joined.
    func currentEntry() async throws -> WaitlistEntryDTO?

    /// Joins the waitlist, or updates the existing entry (upsert on
    /// `profile_id`). `category` must be `nil` for planner-only signups.
    @discardableResult
    func upsert(
        role: WaitlistInterestRole,
        category: VendorRole?,
        region: String
    ) async throws -> WaitlistEntryDTO
}

// MARK: - Environment

/// `nil` until the Supabase-backed service is wired at the scene level in
/// SHIFT-717; ``WaitlistSignupSheet`` treats `nil` as "waitlist unavailable".
private struct WaitlistServiceKey: EnvironmentKey {
    static let defaultValue: (any WaitlistServing)? = nil
}

extension EnvironmentValues {
    var waitlistService: (any WaitlistServing)? {
        get { self[WaitlistServiceKey.self] }
        set { self[WaitlistServiceKey.self] = newValue }
    }
}
