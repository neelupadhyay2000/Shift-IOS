import Foundation
import Models

@MainActor
extension VendorModel {
    /// Projects this vendor to its `event_vendors` wire form.
    ///
    /// The model's contact `phone`/`email` map to the invite-matching columns
    /// (empty → null). `profile_id` / `accepted_at` are null until the invite is
    /// claimed on sign-in, and carry the claim once stamped.
    /// - Throws: `ModelMappingError.missingEvent` if the vendor is detached.
    func toDTO() throws -> EventVendorDTO {
        guard let eventID = event?.id else { throw ModelMappingError.missingEvent }
        return toDTO(eventID: eventID)
    }

    /// Projects this vendor using an explicitly supplied `event_id` — used by the
    /// remote repository, which already knows the owning event.
    ///
    /// A user-entered custom vendor type rides the free-string `role` column in
    /// place of the `custom` raw value — no server schema change. Old clients
    /// map the unknown string back to `.custom` via the decode fallback below.
    func toDTO(eventID: UUID) -> EventVendorDTO {
        EventVendorDTO(
            id: id,
            eventID: eventID,
            profileID: profileId,
            invitedPhone: phone.isEmpty ? nil : phone,
            invitedEmail: email.isEmpty ? nil : email,
            displayName: name,
            role: role == .custom && !customRoleLabel.isEmpty ? customRoleLabel : role.rawValue,
            // Column is integer seconds; the model stores a TimeInterval.
            notificationThreshold: Int(notificationThreshold),
            hasAcknowledgedLatestShift: hasAcknowledgedLatestShift,
            pendingShiftDelta: pendingShiftDelta,
            invitedAt: PostgresTimestamp(invitedAt),
            acceptedAt: PostgresTimestamp(acceptedAt),
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )
    }
}

@MainActor
extension EventVendorDTO {
    /// Builds a fresh `VendorModel` with this row's scalar fields (relationship unwired).
    nonisolated func makeModel() -> VendorModel {
        let model = VendorModel(name: displayName, role: VendorRole(rawValue: role) ?? .custom)
        apply(to: model)
        return model
    }

    /// Overwrites `model`'s scalar fields from this row (upsert by id).
    /// Includes the claim state (`profile_id` / `accepted_at`) so a row claimed
    /// server-side flips to `accepted` locally once it syncs back.
    nonisolated func apply(to model: VendorModel) {
        model.id = id
        model.name = displayName
        // An unrecognized role string is a user-entered custom vendor type:
        // store it as the custom label (mirror of the `toDTO` projection).
        let parsedRole = VendorRole(rawValue: role)
        model.role = parsedRole ?? .custom
        model.customRoleLabel = parsedRole == nil ? role : ""
        model.phone = invitedPhone ?? ""
        model.email = invitedEmail ?? ""
        model.notificationThreshold = TimeInterval(notificationThreshold)
        model.hasAcknowledgedLatestShift = hasAcknowledgedLatestShift
        model.pendingShiftDelta = pendingShiftDelta
        model.invitedAt = invitedAt?.value
        model.profileId = profileID
        model.acceptedAt = acceptedAt?.value
        model.updatedAt = updatedAt?.value
    }

    /// Wires the parent relationship by resolving `event_id` against `events`.
    nonisolated func linkRelationships(_ model: VendorModel, events: [UUID: EventModel]) {
        model.event = events[eventID]
    }
}
