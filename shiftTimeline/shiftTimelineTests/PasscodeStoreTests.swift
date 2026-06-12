import Foundation
@testable import shiftTimeline
import Testing

@Suite("PasscodeStore — record format")
struct PasscodeStoreRecordTests {

    private let salt = Data((0 ..< 16).map { UInt8($0) })

    @Test("same passcode and salt produce the same record")
    func recordIsDeterministic() {
        let a = PasscodeStore.record(for: "123456", salt: salt)
        let b = PasscodeStore.record(for: "123456", salt: salt)
        #expect(a == b)
    }

    @Test("record embeds the salt and a 32-byte digest")
    func recordShape() {
        let record = PasscodeStore.record(for: "123456", salt: salt)
        #expect(record.count == 16 + 32)
        #expect(record.prefix(16) == salt)
    }

    @Test("different salts produce different records for the same passcode")
    func saltChangesRecord() {
        let otherSalt = Data((100 ..< 116).map { UInt8($0) })
        let a = PasscodeStore.record(for: "123456", salt: salt)
        let b = PasscodeStore.record(for: "123456", salt: otherSalt)
        #expect(a != b)
    }

    @Test("matches accepts the right passcode and rejects a wrong one")
    func matchesVerifies() {
        let record = PasscodeStore.record(for: "123456", salt: salt)
        #expect(PasscodeStore.matches("123456", record: record))
        #expect(!PasscodeStore.matches("654321", record: record))
        #expect(!PasscodeStore.matches("", record: record))
    }

    @Test("matches rejects malformed records instead of crashing")
    func matchesRejectsGarbage() {
        #expect(!PasscodeStore.matches("123456", record: Data()))
        #expect(!PasscodeStore.matches("123456", record: Data([0x01, 0x02])))
    }
}
