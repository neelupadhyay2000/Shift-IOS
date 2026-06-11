import Foundation
import Testing
@testable import shiftTimeline

@Suite("Event access — owner vs shared gating")
struct EventAccessTests {

    private let me = UUID()
    private let other = UUID()

    @Test func ownedWhenOwnerMatchesCurrentProfile() {
        #expect(EventAccess.isOwner(ownerId: me, currentProfileID: me))
        #expect(!EventAccess.isShared(ownerId: me, currentProfileID: me))
    }

    @Test func sharedWhenOwnedByAnotherProfile() {
        #expect(EventAccess.isShared(ownerId: other, currentProfileID: me))
        #expect(!EventAccess.isOwner(ownerId: other, currentProfileID: me))
    }

    /// No owner stamped yet (local-only / pre-backfill) → treated as the user's own.
    @Test func ownedWhenOwnerUnknown() {
        #expect(EventAccess.isOwner(ownerId: nil, currentProfileID: me))
        #expect(!EventAccess.isShared(ownerId: nil, currentProfileID: me))
    }

    /// Signed out → never gated; the user keeps full local editing of their data,
    /// even on events that carry an owner id from a previous session.
    @Test func ownedWhenSignedOutEvenIfOwnerSet() {
        #expect(EventAccess.isOwner(ownerId: other, currentProfileID: nil))
        #expect(!EventAccess.isShared(ownerId: other, currentProfileID: nil))
    }

    @Test func ownedWhenBothNil() {
        #expect(EventAccess.isOwner(ownerId: nil, currentProfileID: nil))
        #expect(!EventAccess.isShared(ownerId: nil, currentProfileID: nil))
    }
}
