//
//  VoiceMemoStorageTests.swift
//  shiftTimelineTests
//
//  Coverage for the voice-memo storage helper:
//   * Filename generation is deterministic and contains the block UUID.
//   * `resolve(_:)` returns nil for missing files (CloudKit-synced records
//     whose audio hasn't been transferred to this device).
//   * `resolve(_:)` recovers when the absolute path stored on disk no longer
//     matches the current Documents container (post-restore / reinstall).
//   * `deleteFile(for:)` is idempotent when the file is already gone.
//

import Foundation
import Testing
@testable import shiftTimeline

@Suite("VoiceMemoStorage")
struct VoiceMemoStorageTests {

    // MARK: - Filename generation

    @Test func filenameContainsBlockUUIDAndExtension() {
        let blockID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let filename = VoiceMemoStorage.makeFilename(for: blockID, timestamp: timestamp)

        #expect(filename.hasPrefix("voicememo_\(blockID.uuidString)_"))
        #expect(filename.hasSuffix(".m4a"))
        #expect(filename.contains("\(Int(timestamp.timeIntervalSince1970))"))
    }

    @Test func filenamesAreUniquePerBlockAndTimestamp() {
        let blockA = UUID()
        let blockB = UUID()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_001)

        #expect(VoiceMemoStorage.makeFilename(for: blockA, timestamp: t1)
                != VoiceMemoStorage.makeFilename(for: blockB, timestamp: t1))
        #expect(VoiceMemoStorage.makeFilename(for: blockA, timestamp: t1)
                != VoiceMemoStorage.makeFilename(for: blockA, timestamp: t2))
    }

    @Test func recordingURLIsInsideDocumentsDirectory() throws {
        let docs = try #require(VoiceMemoStorage.documentsDirectory)
        let url = try #require(VoiceMemoStorage.makeRecordingURL(for: UUID()))
        #expect(url.deletingLastPathComponent().path == docs.path)
        #expect(url.pathExtension == "m4a")
    }

    // MARK: - Resolution

    @Test func resolveReturnsNilForNilInput() {
        #expect(VoiceMemoStorage.resolve(nil) == nil)
    }

    @Test func resolveReturnsNilWhenFileDoesNotExist() {
        // Use a synthetic absolute path that definitely does not exist and
        // whose lastPathComponent also does not exist in Documents.
        let bogus = URL(fileURLWithPath: "/private/var/nope/voicememo_\(UUID().uuidString)_0.m4a")
        #expect(VoiceMemoStorage.resolve(bogus) == nil)
    }

    @Test func resolveReturnsAbsoluteURLWhenFileExistsAtStoredPath() throws {
        let url = try makeTempMemoFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let resolved = try #require(VoiceMemoStorage.resolve(url))
        #expect(resolved.path == url.path)
    }

    @Test func resolveFallsBackToDocumentsLookupWhenAbsolutePathIsStale() throws {
        // Simulate the post-restore scenario: a record was saved with an
        // absolute path that no longer exists, but a file with the same
        // lastPathComponent does exist in the current Documents directory.
        let docs = try #require(VoiceMemoStorage.documentsDirectory)
        let filename = VoiceMemoStorage.makeFilename(for: UUID())
        let liveURL = docs.appendingPathComponent(filename)
        try Data([0x00]).write(to: liveURL)
        defer { try? FileManager.default.removeItem(at: liveURL) }

        let stalePath = "/var/mobile/Containers/Data/Application/STALE-CONTAINER/Documents/\(filename)"
        let stale = URL(fileURLWithPath: stalePath)

        let resolved = try #require(VoiceMemoStorage.resolve(stale))
        #expect(resolved.path == liveURL.path)
    }

    // MARK: - Deletion

    @Test func deleteFileRemovesExistingFileAndReturnsTrue() throws {
        let url = try makeTempMemoFile()
        #expect(FileManager.default.fileExists(atPath: url.path))

        let didDelete = VoiceMemoStorage.deleteFile(for: url)
        #expect(didDelete == true)
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test func deleteFileReturnsFalseWhenNothingToDelete() {
        let bogus = URL(fileURLWithPath: "/private/var/nope/missing_\(UUID().uuidString).m4a")
        #expect(VoiceMemoStorage.deleteFile(for: bogus) == false)
        #expect(VoiceMemoStorage.deleteFile(for: nil) == false)
    }

    @Test func deleteFileViaStaleAbsolutePathStillRemovesDocumentsCopy() throws {
        let docs = try #require(VoiceMemoStorage.documentsDirectory)
        let filename = VoiceMemoStorage.makeFilename(for: UUID())
        let liveURL = docs.appendingPathComponent(filename)
        try Data([0x01]).write(to: liveURL)

        let stalePath = "/var/mobile/Containers/Data/Application/STALE/Documents/\(filename)"
        let stale = URL(fileURLWithPath: stalePath)

        let didDelete = VoiceMemoStorage.deleteFile(for: stale)
        #expect(didDelete == true)
        #expect(FileManager.default.fileExists(atPath: liveURL.path) == false)
    }

    // MARK: - Helpers

    private func makeTempMemoFile() throws -> URL {
        let docs = try #require(VoiceMemoStorage.documentsDirectory)
        let url = docs.appendingPathComponent(VoiceMemoStorage.makeFilename(for: UUID()))
        try Data([0xFF, 0xFB]).write(to: url)
        return url
    }
}
