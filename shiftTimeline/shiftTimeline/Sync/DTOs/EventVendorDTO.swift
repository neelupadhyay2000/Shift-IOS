import Foundation

/// Row in the Supabase `event_vendors` table. Mirrors `VendorModel` as a
/// per-event vendor relationship plus invite/claim state.
///
/// `profile_id` is null for contact-only and not-yet-claimed vendors; it is set
/// on claim-on-sign-in. `notification_threshold` is stored as an
/// integer number of **seconds** (the model holds a `TimeInterval`, narrowed in
/// the mapping layer). `role` is coded as plain text (free-text column); the
/// typed `VendorRole` conversion happens in the mapping layer.
nonisolated struct EventVendorDTO: Codable, Equatable {
    let id: UUID
    let eventID: UUID
    let profileID: UUID?
    let invitedPhone: String?
    let invitedEmail: String?
    let displayName: String
    let role: String
    let notificationThreshold: Int
    let hasAcknowledgedLatestShift: Bool
    let pendingShiftDelta: Double?
    let invitedAt: PostgresTimestamp?
    let acceptedAt: PostgresTimestamp?
    let createdAt: PostgresTimestamp?
    let updatedAt: PostgresTimestamp?
    let deletedAt: PostgresTimestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case profileID = "profile_id"
        case invitedPhone = "invited_phone"
        case invitedEmail = "invited_email"
        case displayName = "display_name"
        case role
        case notificationThreshold = "notification_threshold"
        case hasAcknowledgedLatestShift = "has_acknowledged_latest_shift"
        case pendingShiftDelta = "pending_shift_delta"
        case invitedAt = "invited_at"
        case acceptedAt = "accepted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: UUID,
        eventID: UUID,
        profileID: UUID? = nil,
        invitedPhone: String? = nil,
        invitedEmail: String? = nil,
        displayName: String,
        role: String,
        notificationThreshold: Int,
        hasAcknowledgedLatestShift: Bool,
        pendingShiftDelta: Double? = nil,
        invitedAt: PostgresTimestamp? = nil,
        acceptedAt: PostgresTimestamp? = nil,
        createdAt: PostgresTimestamp? = nil,
        updatedAt: PostgresTimestamp? = nil,
        deletedAt: PostgresTimestamp? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.profileID = profileID
        self.invitedPhone = invitedPhone
        self.invitedEmail = invitedEmail
        self.displayName = displayName
        self.role = role
        self.notificationThreshold = notificationThreshold
        self.hasAcknowledgedLatestShift = hasAcknowledgedLatestShift
        self.pendingShiftDelta = pendingShiftDelta
        self.invitedAt = invitedAt
        self.acceptedAt = acceptedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
