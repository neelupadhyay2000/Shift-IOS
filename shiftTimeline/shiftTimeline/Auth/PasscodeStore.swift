import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Keychain-backed six-digit app passcode, created on the first sign-in on
/// this device and required on every app open thereafter.
///
/// Only a salted record (16-byte salt ‖ 32-byte PBKDF2-HMAC-SHA256 digest)
/// is stored — in a this-device-only Keychain item, and mirrored as an opaque
/// blob to the `app_passcodes` table so the passcode follows the account
/// across sign-outs and devices (see `PasscodeSyncService`). PBKDF2 at
/// 150k iterations because the record leaves the device: a 6-digit space
/// must cost an attacker real work per guess if the table ever leaked.
struct PasscodeStore {

    static let requiredLength = 6
    static let kdfIterations = 150_000
    /// First byte of every new record, so future KDF changes can coexist
    /// with stored records instead of silently invalidating passcodes.
    static let recordVersion: UInt8 = 2

    private static let service = "com.neelsoftwaresolutions.shiftTimeline.applock"
    private static let account = "passcode"
    private static let saltLength = 16
    private static let digestLength = 32

    // MARK: - Record format (pure, testable)

    /// `version ‖ salt ‖ PBKDF2-HMAC-SHA256(passcode, salt, 150k)`.
    static func record(for passcode: String, salt: Data) -> Data {
        let digest = pbkdf2Digest(for: passcode, salt: salt)
        guard !digest.isEmpty else { return Data() }
        return Data([recordVersion]) + salt + digest
    }

    /// Verifies `passcode` against a stored record; tolerant of garbage data.
    ///
    /// Unversioned 48-byte records from pre-release dev builds are still
    /// honored (PBKDF2 first, then the original one-shot SHA-256) so a record
    /// minted before versioning keeps validating its passcode.
    static func matches(_ passcode: String, record: Data) -> Bool {
        if record.count == 1 + saltLength + digestLength, record.first == recordVersion {
            let salt = record.subdata(in: 1 ..< 1 + saltLength)
            return self.record(for: passcode, salt: salt) == record
        }

        guard record.count == saltLength + digestLength else { return false }
        let salt = Data(record.prefix(saltLength))
        if salt + pbkdf2Digest(for: passcode, salt: salt) == record { return true }
        var material = salt
        material.append(Data(passcode.utf8))
        return salt + Data(SHA256.hash(data: material)) == record
    }

    /// PBKDF2-HMAC-SHA256 digest; internal so tests can compose legacy records.
    static func pbkdf2Digest(for passcode: String, salt: Data) -> Data {
        var digest = Data(repeating: 0, count: digestLength)
        let status = digest.withUnsafeMutableBytes { digestBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passcode,
                    passcode.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(kdfIterations),
                    digestBytes.bindMemory(to: UInt8.self).baseAddress,
                    digestLength
                )
            }
        }
        guard status == kCCSuccess else { return Data() }
        return digest
    }

    // MARK: - Keychain

    var hasPasscode: Bool { currentRecord() != nil }

    func set(_ passcode: String) {
        var saltBytes = [UInt8](repeating: 0, count: Self.saltLength)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else { return }
        let record = Self.record(for: passcode, salt: Data(saltBytes))
        guard !record.isEmpty else { return }
        setRecord(record)
    }

    /// Installs an opaque record (a server-restored passcode) verbatim.
    func setRecord(_ record: Data) {
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
        guard let record = currentRecord() else { return false }
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

    func currentRecord() -> Data? {
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
