import Foundation

extension String {

    /// Normalizes a phone string to an optional leading "+" followed by
    /// digits only. Returns an empty string when no digits are present.
    ///
    /// Shared by `VendorQuickContactRow` and `VendorAckGrid`.
    var normalizedPhoneDigits: String {
        let stripped = filter { $0.isNumber || $0 == "+" }
        let hasLeadingPlus = stripped.hasPrefix("+")
        let digitsOnly = stripped.filter { $0.isNumber }
        guard !digitsOnly.isEmpty else { return "" }
        return hasLeadingPlus ? "+\(digitsOnly)" : digitsOnly
    }
}
