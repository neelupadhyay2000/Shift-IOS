import Foundation

/// One vendor contact inside a reusable vendor team.
///
/// A plain value snapshot (name, role, contact info) rather than a reference to
/// a `VendorModel` — vendors are per-event entities, so applying a team to an
/// event materialises fresh `VendorModel` rows from these snapshots.
public struct VendorTeamMember: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var role: VendorRole
    /// User-entered vendor type shown when `role == .custom` (e.g. "Videographer").
    public var customRoleLabel: String
    public var phone: String
    public var email: String

    public init(
        id: UUID = UUID(),
        name: String,
        role: VendorRole,
        customRoleLabel: String = "",
        phone: String = "",
        email: String = ""
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.customRoleLabel = customRoleLabel
        self.phone = phone
        self.email = email
    }

    /// Custom decoding so team files written before `customRoleLabel` existed
    /// still load (the key defaults to empty). Encoding stays synthesized.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decode(VendorRole.self, forKey: .role)
        customRoleLabel = try container.decodeIfPresent(String.self, forKey: .customRoleLabel) ?? ""
        phone = try container.decode(String.self, forKey: .phone)
        email = try container.decode(String.self, forKey: .email)
    }
}

/// A reusable, user-defined group of vendors (e.g. "Wedding A-Team") managed
/// in Settings and applied to any event in one tap from the vendor manager.
public struct VendorTeam: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var members: [VendorTeamMember]

    public init(id: UUID = UUID(), name: String, members: [VendorTeamMember] = []) {
        self.id = id
        self.name = name
        self.members = members
    }
}
