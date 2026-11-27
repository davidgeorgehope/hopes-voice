import Foundation

/// Per-profile message-bar behavior. Defaults match a familiar AAC bar.
struct MessageBarSettings: Equatable, Codable, Sendable {
    var speakOnTap: Bool
    var speakOnBarTap: Bool
    var clearAfterSpeak: Bool

    static let `default` = MessageBarSettings(
        speakOnTap: true,
        speakOnBarTap: true,
        clearAfterSpeak: false
    )
}
