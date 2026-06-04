import Foundation
@testable import shiftTimeline
import Testing

// MARK: - ProfileDTO encoding

@Suite("ProfileDTO — encoding")
struct ProfileDTOEncodingTests {
    @Test("encodes id as a UUID string")
    func encodesID() throws {
        let id = UUID()
        let dto = ProfileDTO(id: id, displayName: nil, phone: nil, email: nil)
        let json = try encodeToJSON(dto)
        let encodedID = json["id"] as? String
        #expect(encodedID?.lowercased() == id.uuidString.lowercased())
    }

    @Test("encodes display_name in snake_case, not camelCase")
    func encodesDisplayNameAsSnakeCase() throws {
        let dto = ProfileDTO(id: UUID(), displayName: "Ada Lovelace", phone: nil, email: nil)
        let json = try encodeToJSON(dto)
        #expect(json["display_name"] as? String == "Ada Lovelace")
        #expect(json["displayName"] == nil)
    }

    @Test("omits nil displayName from encoded JSON so existing Postgres values are not overwritten")
    func omitsNilDisplayName() throws {
        let dto = ProfileDTO(id: UUID(), displayName: nil, phone: nil, email: nil)
        let json = try encodeToJSON(dto)
        #expect(json["display_name"] == nil)
    }

    @Test("encodes phone when present")
    func encodesPhone() throws {
        let dto = ProfileDTO(id: UUID(), displayName: nil, phone: "+14155550101", email: nil)
        let json = try encodeToJSON(dto)
        #expect(json["phone"] as? String == "+14155550101")
    }

    @Test("omits nil phone from encoded JSON")
    func omitsNilPhone() throws {
        let dto = ProfileDTO(id: UUID(), displayName: nil, phone: nil, email: nil)
        let json = try encodeToJSON(dto)
        #expect(json["phone"] == nil)
    }

    @Test("encodes email when present")
    func encodesEmail() throws {
        let dto = ProfileDTO(id: UUID(), displayName: nil, phone: nil, email: "ada@example.com")
        let json = try encodeToJSON(dto)
        #expect(json["email"] as? String == "ada@example.com")
    }

    @Test("omits nil email from encoded JSON")
    func omitsNilEmail() throws {
        let dto = ProfileDTO(id: UUID(), displayName: nil, phone: nil, email: nil)
        let json = try encodeToJSON(dto)
        #expect(json["email"] == nil)
    }

    @Test("encodes only id when all optionals are nil — minimal upsert payload")
    func encodesOnlyIDWhenAllNil() throws {
        let dto = ProfileDTO(id: UUID(), displayName: nil, phone: nil, email: nil)
        let json = try encodeToJSON(dto)
        #expect(json.count == 1)
    }

    @Test("encodes id plus all four fields when all are present")
    func encodesAllPresentFields() throws {
        let dto = ProfileDTO(id: UUID(), displayName: "Ada", phone: "+1415", email: "ada@x.com")
        let json = try encodeToJSON(dto)
        #expect(json.count == 4)
    }
}

// MARK: - ProfileDTO decoding

@Suite("ProfileDTO — decoding")
struct ProfileDTODecodingTests {
    @Test("decodes all fields from Postgres-style snake_case JSON")
    func decodesFromSnakeCaseJSON() throws {
        let id = UUID()
        let raw = """
        {
            "id": "\(id.uuidString)",
            "display_name": "Ada Lovelace",
            "phone": "+14155550101",
            "email": "ada@example.com"
        }
        """
        let dto = try decodeProfileDTO(from: raw)
        #expect(dto.id == id)
        #expect(dto.displayName == "Ada Lovelace")
        #expect(dto.phone == "+14155550101")
        #expect(dto.email == "ada@example.com")
    }

    @Test("decodes with missing optional fields as nil")
    func decodesWithMissingOptionals() throws {
        let id = UUID()
        let raw = """
        { "id": "\(id.uuidString)" }
        """
        let dto = try decodeProfileDTO(from: raw)
        #expect(dto.id == id)
        #expect(dto.displayName == nil)
        #expect(dto.phone == nil)
        #expect(dto.email == nil)
    }

    @Test("round-trip: encode then decode produces an equal DTO")
    func roundTrip() throws {
        let original = ProfileDTO(
            id: UUID(),
            displayName: "Ada Lovelace",
            phone: "+14155550101",
            email: "ada@example.com"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProfileDTO.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - SupabaseProfileRepository structural

@Suite("SupabaseProfileRepository")
@MainActor
struct SupabaseProfileRepositoryTests {
    @Test("initializes with a SupabaseClient")
    func initializesWithClient() throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let repo = SupabaseProfileRepository(client: provider.client)
        _ = repo
    }

    @Test("conforms to ProfileRepositing")
    func conformsToProtocol() throws {
        let url = try #require(URL(string: "https://wrhrpyinkcopqsibmkrf.supabase.co"))
        let provider = SupabaseClientProvider(supabaseURL: url, supabaseKey: "test-anon-key")
        let repo: any ProfileRepositing = SupabaseProfileRepository(client: provider.client)
        _ = repo
    }
}

// MARK: - Helpers

private func encodeToJSON(_ dto: ProfileDTO) throws -> [String: Any] {
    let data = try JSONEncoder().encode(dto)
    let obj = try JSONSerialization.jsonObject(with: data)
    return try #require(obj as? [String: Any])
}

private func decodeProfileDTO(from jsonString: String) throws -> ProfileDTO {
    let data = try #require(jsonString.data(using: .utf8))
    return try JSONDecoder().decode(ProfileDTO.self, from: data)
}
