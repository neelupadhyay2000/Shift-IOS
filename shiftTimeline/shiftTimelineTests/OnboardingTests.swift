import Foundation
@testable import shiftTimeline
import Testing

@Suite("Onboarding — completion payload + ProfileDTO.onboarded gate")
struct OnboardingTests {

    // MARK: OnboardingCompletionDTO

    @Test("completion payload always sends onboarded=true; omits nil fields")
    func completionEncoding() throws {
        let payload = OnboardingCompletionDTO(displayName: "Neel", defaultRole: "planner", bio: nil)
        let json = try jsonObject(from: payload)
        #expect(json["onboarded"] as? Bool == true)
        #expect(json["display_name"] as? String == "Neel")
        #expect(json["default_role"] as? String == "planner")
        #expect(json["bio"] == nil)             // nil omitted, not clobbered
    }

    @Test("completion payload encodes bio when present")
    func completionEncodingBio() throws {
        let payload = OnboardingCompletionDTO(displayName: nil, defaultRole: nil, bio: "Weddings")
        let json = try jsonObject(from: payload)
        #expect(json["onboarded"] as? Bool == true)
        #expect(json["bio"] as? String == "Weddings")
        #expect(json["display_name"] == nil)
        #expect(json["default_role"] == nil)
    }

    // MARK: ProfileDTO.onboarded round-trips and is never encoded

    @Test("ProfileDTO decodes onboarded but never encodes it")
    func profileOnboardedCoding() throws {
        let id = UUID()
        let decoded = try decodeDTO(ProfileDTO.self, from: """
        { "id": "\(id.uuidString)", "display_name": "Neel", "onboarded": true }
        """)
        #expect(decoded.onboarded == true)

        // The generic upsert must never post onboarded (so a session restore can't
        // reset it) — verify it's absent from the encoded payload.
        let json = try jsonObject(from: ProfileDTO(id: id, displayName: "Neel", phone: nil, email: nil, onboarded: true))
        #expect(json["onboarded"] == nil)
        #expect(json["display_name"] as? String == "Neel")
    }

    @Test("ProfileDTO tolerates a missing onboarded key")
    func profileOnboardedMissing() throws {
        let decoded = try decodeDTO(ProfileDTO.self, from: """
        { "id": "\(UUID().uuidString)", "display_name": "A" }
        """)
        #expect(decoded.onboarded == nil)
    }
}
