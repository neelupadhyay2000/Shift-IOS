import Foundation
import Testing
@testable import shiftTimeline

@Suite("Block detail scoping (SHIFT-630)")
struct BlockDetailScopeTests {

    private let me = UUID()
    private let other = UUID()

    @Test func ownerSeesFullDetailRegardlessOfAssignment() {
        // isReadOnly == false → the owner; assignment is irrelevant.
        #expect(BlockDetailScope.showsFullDetail(isReadOnly: false, assignedProfileIDs: [], currentProfileID: me))
        #expect(BlockDetailScope.showsFullDetail(isReadOnly: false, assignedProfileIDs: [other], currentProfileID: me))
    }

    @Test func vendorSeesFullDetailOnlyWhenAssigned() {
        #expect(BlockDetailScope.showsFullDetail(isReadOnly: true, assignedProfileIDs: [me], currentProfileID: me))
        #expect(BlockDetailScope.showsFullDetail(isReadOnly: true, assignedProfileIDs: [other, me], currentProfileID: me))
    }

    @Test func vendorDeniedDetailWhenNotAssigned() {
        #expect(!BlockDetailScope.showsFullDetail(isReadOnly: true, assignedProfileIDs: [other], currentProfileID: me))
        #expect(!BlockDetailScope.showsFullDetail(isReadOnly: true, assignedProfileIDs: [], currentProfileID: me))
    }

    @Test func vendorDeniedDetailWhenSignedOut() {
        #expect(!BlockDetailScope.showsFullDetail(isReadOnly: true, assignedProfileIDs: [me], currentProfileID: nil))
    }
}
