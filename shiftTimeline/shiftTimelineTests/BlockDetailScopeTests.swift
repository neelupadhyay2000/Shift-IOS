import Foundation
import Models
import Services
@testable import shiftTimeline
import SwiftData
import Testing

@Suite("Block detail scoping")
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

    // MARK: - block.isAssigned(to:) — drives the "Assigned" timeline indicator

    @MainActor
    @Test("a block is assigned to the viewer iff an assigned vendor carries their profile id")
    func blockIsAssignedReflectsVendorProfile() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let block = TimeBlockModel(title: "Ceremony", scheduledStart: .now, duration: 1800)
        let mine = VendorModel(name: "DJ", role: .dj)
        mine.profileId = me
        let theirs = VendorModel(name: "Florist", role: .florist)
        theirs.profileId = other
        context.insert(block)
        context.insert(mine)
        context.insert(theirs)
        block.vendors = [mine, theirs]
        try context.save()

        #expect(block.isAssigned(to: me))      // I'm an assigned vendor
        #expect(block.isAssigned(to: other))   // so is the other vendor
        #expect(!block.isAssigned(to: UUID()))  // a stranger isn't
        #expect(!block.isAssigned(to: nil))     // signed-out → never
    }

    @MainActor
    @Test("a block with no assigned vendors is assigned to no one")
    func unassignedBlockIsAssignedToNoOne() throws {
        let container = try PersistenceController.forTesting()
        let context = container.mainContext
        let block = TimeBlockModel(title: "Setup", scheduledStart: .now, duration: 600)
        context.insert(block)
        try context.save()

        #expect(!block.isAssigned(to: me))
    }
}
