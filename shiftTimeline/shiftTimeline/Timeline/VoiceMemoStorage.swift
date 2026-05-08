import Foundation

/// Manages voice-memo file URLs in the app's Documents directory.
/// Never trusts stored absolute paths — always re-resolves by `lastPathComponent` (container path is unstable).
enum VoiceMemoStorage {

    static var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// Canonical filename for a memo associated with `blockID`.
    static func makeFilename(for blockID: UUID, timestamp: Date = .now) -> String {
        "voicememo_\(blockID.uuidString)_\(Int(timestamp.timeIntervalSince1970)).m4a"
    }

    /// Absolute recording URL in Documents. `nil` if Documents is unavailable.
    static func makeRecordingURL(for blockID: UUID, timestamp: Date = .now) -> URL? {
        guard let docs = documentsDirectory else { return nil }
        return docs.appendingPathComponent(makeFilename(for: blockID, timestamp: timestamp))
    }

    /// Resolves a stored URL to an existing file URL on this device. Re-resolves by filename; returns `nil` if missing.
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

    /// Removes the file for a stored URL if present. Tolerates missing files.
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
