import Foundation

// MARK: - Reportable content

/// What a report or block targets. Raw values match the
/// `content_reports.content_type` CHECK constraint exactly. `vendor_profile` is
/// the only surface live at marketplace launch; `review` / `message` are wired
/// ahead of E12/E13 so the safety menu is reusable when those ship.
enum ReportableContentType: String, Codable, CaseIterable, Sendable {
    case vendorProfile = "vendor_profile"
    case portfolioItem = "portfolio_item"
    case review
    case message
}

// MARK: - Report reason

/// User-facing report reasons. The raw value is what we persist in
/// `content_reports.reason` (a free-text column, no CHECK) — display strings live
/// with the UI, mirroring the `WaitlistInterestRole` convention.
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam
    case offensive
    case harassment
    case misleading
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spam:       String(localized: "Spam or scam")
        case .offensive:  String(localized: "Offensive or inappropriate")
        case .harassment: String(localized: "Harassment or hate")
        case .misleading: String(localized: "Misleading or fake")
        case .other:      String(localized: "Something else")
        }
    }
}

// MARK: - Content report DTO

/// Write payload for `content_reports`. `created_at` / `status` are server-managed
/// and never sent; the unique `(reporter_id, content_type, content_id)` makes the
/// upsert idempotent (re-reporting the same content updates the reason).
nonisolated struct ContentReportDTO: Codable, Equatable {
    let reporterID: UUID
    let contentType: String
    let contentID: UUID
    let reason: String

    enum CodingKeys: String, CodingKey {
        case reporterID = "reporter_id"
        case contentType = "content_type"
        case contentID = "content_id"
        case reason
    }
}

// MARK: - User block DTO

/// Write payload / read row for `user_blocks`. The pair `(blocker_id, blocked_id)`
/// is the primary key, so the upsert is idempotent.
nonisolated struct UserBlockDTO: Codable, Equatable {
    let blockerID: UUID
    let blockedID: UUID

    enum CodingKeys: String, CodingKey {
        case blockerID = "blocker_id"
        case blockedID = "blocked_id"
    }
}
