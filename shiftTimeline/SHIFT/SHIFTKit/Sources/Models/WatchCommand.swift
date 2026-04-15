import Foundation

/// Command sent from Watch → iPhone via `sendMessage` or `transferUserInfo`.
///
/// The iPhone processes the command (e.g. runs RippleEngine for a shift)
/// and replies with an updated ``WatchContext``.
public struct WatchCommand: Codable, Sendable, Equatable {

    public enum Action: String, Codable, Sendable {
        case shift
        case completeBlock
    }

    public let action: Action
    public let deltaMinutes: Int?

    public init(action: Action, deltaMinutes: Int? = nil) {
        self.action = action
        self.deltaMinutes = deltaMinutes
    }

    // MARK: - WCSession Dictionary Encoding

    /// Encodes to a `[String: Any]` dictionary for `sendMessage` / `transferUserInfo`.
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "command": action.rawValue,
        ]
        if let deltaMinutes {
            dict["minutes"] = deltaMinutes
        }
        return dict
    }

    /// Decodes from a `[String: Any]` dictionary received via
    /// `session(_:didReceiveMessage:)` or `session(_:didReceiveUserInfo:)`.
    public init?(dictionary: [String: Any]) {
        guard let commandString = dictionary["command"] as? String,
              let action = Action(rawValue: commandString)
        else {
            return nil
        }
        self.action = action
        self.deltaMinutes = dictionary["minutes"] as? Int
    }
}
