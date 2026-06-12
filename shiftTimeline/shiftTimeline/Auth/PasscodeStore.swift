import CryptoKit
import Foundation
import Security

/// Keychain-backed six-digit app passcode, created on the first sign-in on
/// this device and required on every app open thereafter.
///
/// Only a salted SHA-256 record (16-byte salt ‖ 32-byte digest) is stored,
/// as a this-device-only Keychain item: the passcode never leaves the device,
/// never restores onto another one, and is wiped on sign-out — a new device
/// (or a fresh sign-in) always re-authenticates with email OTP first.
struct PasscodeStore {

    static let requiredLength = 6

    private static let service = "com.neelsoftwaresolutions.shiftTimeline.applock"
    private static let account = "passcode"
    private static let saltLength = 16

    // MARK: - Record format (pure, testable)

    /// `salt ‖ SHA256(salt ‖ utf8(passcode))`.
    static func record(for passcode: String, salt: Data) -> Data {
        var material = salt
        material.append(Data(passcode.utf8))
        return salt + Data(SHA256.hash(data: material))
    }

    /// Verifies `passcode` against a stored record; tolerant of garbage data.
    static func matches(_ passcode: String, record: Data) -> Bool {
        guard record.count > saltLength else { return false }
        let salt = Data(record.prefix(saltLength))
        return self.record(for: passcode, salt: salt) == record
    }

    // MARK: - Keychain

    var hasPasscode: Bool { readRecord() != nil }

    func set(_ passcode: String) {
        var saltBytes = [UInt8](repeating: 0, count: Self.saltLength)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else { return }
        let record = Self.record(for: passcode, salt: Data(saltBytes))

        clear()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: record,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func validate(_ passcode: String) -> Bool {
        guard let record = readRecord() else { return false }
        return Self.matches(passcode, record: record)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func readRecord() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
