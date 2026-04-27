import Foundation

/// Storage helper for voice-memo audio files.
///
/// Voice memos are written to the app's `Documents` directory. The app
/// container path is **not stable** across reinstalls or device restores, so
/// we never trust a previously-stored absolute URL. Instead, on read we
/// always resolve the file by its `lastPathComponent` against the current
/// `Documents` directory.
///
/// CloudKit-synced records that arrive from another device will reference an
/// absolute path that doesn't exist locally; `resolve(_:)` returns `nil` in
/// that case so the UI can degrade gracefully without erasing the field.
enum VoiceMemoStorage {

    /// Returns the current Documents directory, or `nil` if the platform
    /// cannot vend one (effectively never on iOS).
    static var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// Builds the canonical filename for a memo associated with `blockID`.
    static func makeFilename(for blockID: UUID, timestamp: Date = .now) -> String {
        "voicememo_\(blockID.uuidString)_\(Int(timestamp.timeIntervalSince1970)).m4a"
    }

    /// Builds an absolute file URL inside the current Documents directory for
    /// a freshly-recorded memo. Returns `nil` if Documents is unavailable.
    static func makeRecordingURL(for blockID: UUID, timestamp: Date = .now) -> URL? {
        guard let docs = documentsDirectory else { return nil }
        return docs.appendingPathComponent(makeFilename(for: blockID, timestamp: timestamp))
    }

    /// Resolves a stored URL into a file URL that exists on this device, or
    /// `nil` if the file cannot be found.
    ///
    /// Resolution order:
    /// 1. If `stored` is absolute and the file exists at that path, return it.
    /// 2. Otherwise, look up `Documents/<lastPathComponent>` on the current
    ///    device and return it if the file exists.
    /// 3. Return `nil` (file is missing — likely a CloudKit-synced record
    ///    referencing audio that hasn't been transferred to this device).
    static func resolve(_ stored: URL?) -> URL? {
        guard let stored else { return nil }
        let fm = FileManager.default

        if stored.isFileURL, fm.fileExists(atPath: stored.path) {
            return stored
        }

        let filename = stored.lastPathComponent
        guard !filename.isEmpty, let docs = documentsDirectory else { return nil }
        let candidate = docs.appendingPathComponent(filename)
        return fm.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Removes the on-disk file for a stored memo URL, if present. Tolerates
    /// missing files. The caller is responsible for clearing the model field.
    @discardableResult
    static func deleteFile(for stored: URL?) -> Bool {
        guard let resolved = resolve(stored) else { return false }
        do {
            try FileManager.default.removeItem(at: resolved)
            return true
        } catch {
            return false
        }
    }
}
