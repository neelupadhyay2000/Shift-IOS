import Foundation
import Testing
@testable import shiftTimeline

/// In-process fake `DeviceTokenWriting` — records the upserts it was asked to make.
/// @MainActor + final gives implicit Sendable (mirrors the other fakes).
@MainActor
final class FakeDeviceTokenWriter: DeviceTokenWriting {
    private(set) var calls: [(apnsToken: String, environment: String)] = []
    var shouldThrow = false

    func upsert(apnsToken: String, environment: String) async throws {
        if shouldThrow { throw URLError(.badServerResponse) }
        calls.append((apnsToken, environment))
    }
}

@Suite("Device token registration (SHIFT-642)")
@MainActor
struct DeviceTokenRegistrarTests {

    private let profileA = UUID()
    private let profileB = UUID()

    private func token(_ bytes: [UInt8]) -> Data { Data(bytes) }

    @Test("does not register until both a token and a signed-in profile exist")
    func waitsForBoth() async {
        let writer = FakeDeviceTokenWriter()
        let registrar = DeviceTokenRegistrar(writer: writer, environment: APNsEnvironment.sandbox)

        await registrar.updateAPNsToken(token([0xde, 0xad]))
        #expect(writer.calls.isEmpty)

        await registrar.updateProfile(profileA)
        #expect(writer.calls.count == 1)
    }

    @Test("registers token + environment regardless of arrival order (profile first)")
    func profileThenToken() async {
        let writer = FakeDeviceTokenWriter()
        let registrar = DeviceTokenRegistrar(writer: writer, environment: APNsEnvironment.prod)

        await registrar.updateProfile(profileA)
        #expect(writer.calls.isEmpty)

        await registrar.updateAPNsToken(token([0xbe, 0xef]))
        #expect(writer.calls.count == 1)
        #expect(writer.calls.first?.environment == "prod")
    }

    @Test("encodes the APNs token Data as lowercase hex")
    func hexEncoding() async {
        let writer = FakeDeviceTokenWriter()
        let registrar = DeviceTokenRegistrar(writer: writer, environment: APNsEnvironment.sandbox)

        await registrar.updateProfile(profileA)
        await registrar.updateAPNsToken(token([0x00, 0x0f, 0xa1, 0xff]))

        #expect(writer.calls.first?.apnsToken == "000fa1ff")
    }

    @Test("does not re-register an identical token + profile + environment")
    func dedupesIdenticalState() async {
        let writer = FakeDeviceTokenWriter()
        let registrar = DeviceTokenRegistrar(writer: writer, environment: APNsEnvironment.sandbox)

        await registrar.updateProfile(profileA)
        await registrar.updateAPNsToken(token([0x01]))
        await registrar.updateAPNsToken(token([0x01]))
        await registrar.updateProfile(profileA)

        #expect(writer.calls.count == 1)
    }

    @Test("re-registers when the signed-in profile changes (account switch)")
    func reregistersOnAccountSwitch() async {
        let writer = FakeDeviceTokenWriter()
        let registrar = DeviceTokenRegistrar(writer: writer, environment: APNsEnvironment.sandbox)

        await registrar.updateAPNsToken(token([0x01]))
        await registrar.updateProfile(profileA)
        await registrar.updateProfile(profileB)

        #expect(writer.calls.count == 2)
    }

    @Test("re-registers when APNs issues a new token")
    func reregistersOnTokenRefresh() async {
        let writer = FakeDeviceTokenWriter()
        let registrar = DeviceTokenRegistrar(writer: writer, environment: APNsEnvironment.sandbox)

        await registrar.updateProfile(profileA)
        await registrar.updateAPNsToken(token([0x01]))
        await registrar.updateAPNsToken(token([0x02]))

        #expect(writer.calls.map(\.apnsToken) == ["01", "02"])
    }

    @Test("sign-out then sign-in re-registers (dedupe is cleared)")
    func signOutResetsDedupe() async {
        let writer = FakeDeviceTokenWriter()
        let registrar = DeviceTokenRegistrar(writer: writer, environment: APNsEnvironment.sandbox)

        await registrar.updateAPNsToken(token([0x01]))
        await registrar.updateProfile(profileA)
        await registrar.updateProfile(nil)
        await registrar.updateProfile(profileA)

        #expect(writer.calls.count == 2)
    }

    @Test("a failed registration is retried on the next trigger")
    func retriesAfterFailure() async {
        let writer = FakeDeviceTokenWriter()
        writer.shouldThrow = true
        let registrar = DeviceTokenRegistrar(writer: writer, environment: APNsEnvironment.sandbox)

        await registrar.updateProfile(profileA)
        await registrar.updateAPNsToken(token([0x01]))
        #expect(writer.calls.isEmpty)

        writer.shouldThrow = false
        await registrar.updateAPNsToken(token([0x01]))
        #expect(writer.calls.count == 1)
    }

    @Test("buffers token + profile until a writer is configured, then registers")
    func buffersUntilConfigured() async {
        let registrar = DeviceTokenRegistrar(environment: APNsEnvironment.sandbox)

        await registrar.updateProfile(profileA)
        await registrar.updateAPNsToken(token([0x01]))

        let writer = FakeDeviceTokenWriter()
        await registrar.configure(writer: writer)

        #expect(writer.calls.count == 1)
    }
}
