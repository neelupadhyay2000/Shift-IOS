import Foundation
import Models

/// Resolves the role label shown for a vendor or team member: the user-entered
/// custom type when the role is `.custom` (e.g. "Videographer"), otherwise the
/// built-in role name.
enum VendorRoleLabel {

    static func display(role: VendorRole, customLabel: String) -> String {
        let trimmed = customLabel.trimmingCharacters(in: .whitespaces)
        return role == .custom && !trimmed.isEmpty ? trimmed : role.displayName
    }
}
