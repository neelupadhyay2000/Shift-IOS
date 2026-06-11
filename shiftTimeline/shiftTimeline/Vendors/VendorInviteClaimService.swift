import Foundation
import Models
import Services

/// Links a signing-in vendor to the `event_vendors` invite(s) addressed to them
///: for every unclaimed, invited row whose locked phone/email matches
/// the signed-in identity, it stamps `profileId` + `acceptedAt` — flipping the
/// invite status from `invited` to `accepted` — and persists.
///
/// Matching is delegated to `VendorInviteClaim`, the shared rule the
/// security-definer claim RPC enforces authoritatively server-side;
/// this client-side pass keeps the local cache convergent with that result.
@MainActor
struct VendorInviteClaimService {

    private let repository: any VendorRepositing
    private let now: () -> Date

    init(repository: any VendorRepositing, now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    /// Claims every invite in `candidates` that `identity` is entitled to.
    ///
    /// A row is claimed only when it is genuinely invited (`invitedAt` set), still
    /// unclaimed (`profileId == nil`), and its locked contact matches `identity`.
    /// Already-claimed rows are never re-linked, so a second sign-in is a no-op.
    ///
    /// - Returns: the rows newly linked to the signed-in profile (empty if none).
    @discardableResult
    func claimMatchingInvites(
        for identity: VendorInviteClaimIdentity,
        among candidates: [VendorModel]
    ) async throws -> [VendorModel] {
        let claimed = candidates.filter { vendor in
            vendor.profileId == nil
                && vendor.invitedAt != nil
                && VendorInviteClaim.matches(
                    invitedPhone: vendor.phone,
                    invitedEmail: vendor.email,
                    identityPhone: identity.phone,
                    identityEmail: identity.email
                )
        }

        guard !claimed.isEmpty else { return [] }

        let acceptedAt = now()
        for vendor in claimed {
            vendor.profileId = identity.profileID
            vendor.acceptedAt = acceptedAt
        }
        try await repository.save()
        return claimed
    }
}
