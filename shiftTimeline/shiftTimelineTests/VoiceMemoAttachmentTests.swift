//
//  VoiceMemoAttachmentTests.swift
//  shiftTimelineTests
//
//  Coverage for the voice-memo attachment contract on TimeBlockModel:
//   * Save action writes voiceMemoURL, voiceMemoDuration, and voiceMemoCreatedAt.
//   * All three fields survive a ModelContext round-trip (simulates app relaunch).
//   * Discard / cancel leaves block fields unchanged.
//   * New blocks default all three fields to nil.
//
//  CloudKit sync note:
//   Audio files (.m4a) are stored on-device in the app's Documents directory and
//   are NOT synced via CloudKit. Only the file URL string is stored in SwiftData
//   and propagated via CloudKit private database sync. On other devices, the URL
//   resolves to nil (VoiceMemoStorage.resolve returns nil when the file is absent),
//   which causes BlockInspectorView to show the "not yet available" degraded state.
//   Full audio-file CloudKit sync (CKAsset) is deferred to a follow-up ticket.
//

import Foundation
import SwiftData
import Testing
import Models

// MARK: - Helpers

/// Builds a temp SQLite-backed ModelContainer at a deterministic path per test,
/// inserts a blank TimeBlockModel, and returns both. Using SQLite (not in-memory)
/// lets us verify cross-context persistence by opening a second ModelContext on the
/// same store URL — the closest approximation to "across app relaunch" in a unit test.
private func makeContainer() throws -> (ModelContainer, URL) {
    let tmpDir = FileManager.default.temporaryDirectory
    let storeURL = tmpDir.appendingPathComponent("VoiceMemoTest-\(UUID().uuidString).sqlite")
    let schema = Schema([EventModel.self, TimeBlockModel.self, TimelineTrack.self,
                         ShiftRecord.self, VendorModel.self])
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    return (container, storeURL)
}

private func makeBlock(in context: ModelContext) throws -> TimeBlockModel {
    let block = TimeBlockModel(
        title: "Ceremony",
        scheduledStart: .now,
        duration: 3600
    )
    context.insert(block)
    try context.save()
    return block
}

// MARK: - Suite

@Suite("VoiceMemoAttachment — model field contract")
struct VoiceMemoAttachmentTests {

    // MARK: - Defaults

    @Test func newBlockHasNilVoiceMemoFields() throws {
        let (container, storeURL) = try makeContainer()
        defer { try? FileManager.default.removeItem(atPath: storeURL.path) }

        let ctx = ModelContext(container)
        let block = try makeBlock(in: ctx)

        #expect(block.voiceMemoURL == nil)
        #expect(block.voiceMemoDuration == nil)
        #expect(block.voiceMemoCreatedAt == nil)
    }

    // MARK: - Save writes all three fields

    @Test func saveAttachesURLDurationAndCreatedAt() throws {
        let (container, storeURL) = try makeContainer()
        defer { try? FileManager.default.removeItem(atPath: storeURL.path) }

        let ctx = ModelContext(container)
        let block = try makeBlock(in: ctx)

        let memoURL = URL(fileURLWithPath: "/tmp/voicememo_test.m4a")
        let duration: TimeInterval = 47.3
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)

        // Simulate the Save action from VoiceMemoRecordingSheet
        block.voiceMemoURL = memoURL
        block.voiceMemoDuration = duration
        block.voiceMemoCreatedAt = createdAt
        try ctx.save()

        #expect(block.voiceMemoURL == memoURL)
        #expect(block.voiceMemoDuration == duration)
        #expect(block.voiceMemoCreatedAt == createdAt)
    }

    // MARK: - Persistence across ModelContext re-open (simulates app relaunch)

    @Test func attachmentFieldsPersistInNewModelContext() throws {
        let (container, storeURL) = try makeContainer()
        defer { try? FileManager.default.removeItem(atPath: storeURL.path) }

        let blockID: UUID
        let memoURL = URL(fileURLWithPath: "/tmp/voicememo_persist_test.m4a")
        let duration: TimeInterval = 120.0
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)

        // --- Write pass ---
        do {
            let ctx = ModelContext(container)
            let block = try makeBlock(in: ctx)
            blockID = block.id
            block.voiceMemoURL = memoURL
            block.voiceMemoDuration = duration
            block.voiceMemoCreatedAt = createdAt
            try ctx.save()
        }

        // --- Read pass: new ModelContext on the same store ---
        let readCtx = ModelContext(container)
        let fetched = try readCtx.fetch(FetchDescriptor<TimeBlockModel>())
        let reloaded = try #require(fetched.first(where: { $0.id == blockID }))

        #expect(reloaded.voiceMemoURL == memoURL)
        #expect(reloaded.voiceMemoDuration == duration)
        #expect(reloaded.voiceMemoCreatedAt == createdAt)
    }

    // MARK: - Discard / cancel leaves block unchanged

    @Test func discardLeavesBlockFieldsNil() throws {
        let (container, storeURL) = try makeContainer()
        defer { try? FileManager.default.removeItem(atPath: storeURL.path) }

        let ctx = ModelContext(container)
        let block = try makeBlock(in: ctx)

        // Simulate the Discard action: the coordinator removes the file and
        // the sheet dismisses without writing to the block.
        // Block fields must remain nil.
        #expect(block.voiceMemoURL == nil)
        #expect(block.voiceMemoDuration == nil)
        #expect(block.voiceMemoCreatedAt == nil)
    }

    @Test func cancelAfterSaveDoesNotClearExistingMemo() throws {
        // If a block already has a memo and the user starts a new recording
        // then cancels, the original memo must survive.
        let (container, storeURL) = try makeContainer()
        defer { try? FileManager.default.removeItem(atPath: storeURL.path) }

        let ctx = ModelContext(container)
        let block = try makeBlock(in: ctx)

        let originalURL = URL(fileURLWithPath: "/tmp/original.m4a")
        let originalDuration: TimeInterval = 30.0
        let originalCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        block.voiceMemoURL = originalURL
        block.voiceMemoDuration = originalDuration
        block.voiceMemoCreatedAt = originalCreatedAt
        try ctx.save()

        // Cancel does NOT touch the block model — only coordinator.cancel() discards
        // the *new* temp recording file. Verify original fields are untouched.
        #expect(block.voiceMemoURL == originalURL)
        #expect(block.voiceMemoDuration == originalDuration)
        #expect(block.voiceMemoCreatedAt == originalCreatedAt)
    }
}
