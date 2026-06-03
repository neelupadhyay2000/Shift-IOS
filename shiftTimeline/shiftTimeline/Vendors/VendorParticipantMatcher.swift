import Foundation

/// Sendable snapshot of a CKShare participant's identity, extracted from
/// `CKShare.Participant.userIdentity` so the matching logic stays pure and
/// testable (no CloudKit types).
nonisolated struct ParticipantInfo: Equatable {
    let recordName: String?   // userIdentity.userRecordID?.recordName — nil until accepted
    let email: String?        // lookupInfo.emailAddress (how they were invited)
    let phone: String?        // lookupInfo.phoneNumber
}

/// The minimal vendor data needed to match against a participant.
nonisolated struct VendorRef: Equatable {
    let id: UUID
    let email: String
    let phone: String
}

/// Result of a successful link: which vendor to stamp with which record name.
nonisolated struct VendorMatch: Equatable {
    let vendorID: UUID
    let recordName: String
}

/// Maps accepted CKShare participants back to the planner's `VendorModel`s by
/// the email/phone they were invited with — the claim-on-accept correlation.
///
/// Pure and Sendable-input so it's unit-tested without CloudKit. Phone matching
/// tolerates country-code differences (CloudKit returns E.164; vendors are often
/// stored as a local formatted number) via suffix comparison with a min length.
nonisolated enum VendorParticipantMatcher {

    static func match(participants: [ParticipantInfo], vendors: [VendorRef]) -> [VendorMatch] {
        var results: [VendorMatch] = []

        for participant in participants {
            // No record name = the participant hasn't accepted yet — nothing to link.
            guard let recordName = participant.recordName, !recordName.isEmpty else { continue }

            // Prefer phone match (how we invite), then exact email.
            if let phone = participant.phone, !phone.isEmpty,
               let vendor = vendors.first(where: { !$0.phone.isEmpty && phoneMatches($0.phone, phone) }) {
                results.append(VendorMatch(vendorID: vendor.id, recordName: recordName))
                continue
            }

            if let email = participant.email, !email.isEmpty {
                let lowered = email.lowercased()
                if let vendor = vendors.first(where: { !$0.email.isEmpty && $0.email.lowercased() == lowered }) {
                    results.append(VendorMatch(vendorID: vendor.id, recordName: recordName))
                    continue
                }
            }
        }

        return results
    }

    /// Two phone numbers match if their digit tails agree. Requires ≥7 digits on
    /// the shorter side so short strings can't loosely suffix-match. Handles the
    /// "+1 5551112222" vs "(555) 111-2222" case.
    static func phoneMatches(_ a: String, _ b: String) -> Bool {
        let da = a.normalizedPhoneDigits.filter(\.isNumber)
        let db = b.normalizedPhoneDigits.filter(\.isNumber)
        guard da.count >= 7, db.count >= 7 else { return false }
        return da == db || da.hasSuffix(db) || db.hasSuffix(da)
    }
}
