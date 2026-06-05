import Foundation
import Models

@MainActor
extension VendorModel {
    /// Projects this vendor to its `event_vendors` wire form.
    ///
    /// The local model predates the invite/claim columns, so `profile_id` and
    /// `accepted_at` are sent null — they become authoritative in E14. The
    /// model's contact `phone`/`email` map to the invite-matching columns; an
    /// empty contact string maps to null.
    /// - Throws: `ModelMappingError.missingEvent` if the vendor is detached.
    func toDTO() throws -> EventVendorDTO {
        guard let eventID = event?.id else { throw ModelMappingError.missingEvent }
        return toDTO(eventID: eventID)
    }

    /// Projects this vendor using an explicitly supplied `event_id` — used by the
    /// remote repository, which already knows the owning event.
    func toDTO(eventID: UUID) -> EventVendorDTO {
        EventVendorDTO(
            id: id,
            eventID: eventID,
            profileID: nil,
            invitedPhone: phone.isEmpty ? nil : phone,
            invitedEmail: email.isEmpty ? nil : email,
            displayName: name,
            role: role.rawValue,
            // Column is integer seconds; the model stores a TimeInterval.
            notificationThreshold: Int(notificationThreshold),
            hasAcknowledgedLatestShift: hasAcknowledgedLatestShift,
            pendingShiftDelta: pendingShiftDelta,
            invitedAt: PostgresTimestamp(invitedAt),
            acceptedAt: nil,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )
    }
}

@MainActor
extension EventVendorDTO {
    /// Builds a fresh `VendorModel` with this row's scalar fields (relationship unwired).
    func makeModel() -> VendorModel {
        let model = VendorModel(name: displayName, role: VendorRole(rawValue: role) ?? .custom)
        apply(to: model)
        return model
    }

    /// Overwrites `model`'s scalar fields from this row (upsert by id).
    /// `profile_id` / `accepted_at` have no local column and are not applied.
    func apply(to model: VendorModel) {
        model.id = id
        model.name = displayName
        model.role = VendorRole(rawValue: role) ?? .custom
        model.phone = invitedPhone ?? ""
        model.email = invitedEmail ?? ""
        model.notificationThreshold = TimeInterval(notificationThreshold)
        model.hasAcknowledgedLatestShift = hasAcknowledgedLatestShift
        model.pendingShiftDelta = pendingShiftDelta
        model.invitedAt = invitedAt?.value
    }

    /// Wires the parent relationship by resolving `event_id` against `events`.
    func linkRelationships(_ model: VendorModel, events: [UUID: EventModel]) {
        model.event = events[eventID]
    }
}
