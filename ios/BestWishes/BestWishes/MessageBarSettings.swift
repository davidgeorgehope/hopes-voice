import Foundation

/// Per-profile message-bar behavior and look.
struct MessageBarSettings: Equatable, Codable, Sendable {
    var speakOnTap: Bool
    var speakOnBarTap: Bool
    var clearAfterSpeak: Bool
    /// `standard` (cream chip well) or `compactBlue` (solid bar, label above picture, trailing delete-last).
    var style: String
    var backgroundHex: String?
    var textAboveImage: Bool
    var showDeleteLast: Bool

    static let `default` = MessageBarSettings(
        speakOnTap: true,
        speakOnBarTap: true,
        clearAfterSpeak: false,
        style: "standard",
        backgroundHex: nil,
        textAboveImage: false,
        showDeleteLast: true
    )

    static let compactBlue = MessageBarSettings(
        speakOnTap: true,
        speakOnBarTap: true,
        clearAfterSpeak: true,
        style: "compactBlue",
        backgroundHex: "0000CB",
        textAboveImage: true,
        showDeleteLast: true
    )

    enum CodingKeys: String, CodingKey {
        case speakOnTap, speakOnBarTap, clearAfterSpeak, style, backgroundHex, textAboveImage, showDeleteLast
    }

    init(
        speakOnTap: Bool,
        speakOnBarTap: Bool,
        clearAfterSpeak: Bool,
        style: String = "standard",
        backgroundHex: String? = nil,
        textAboveImage: Bool = false,
        showDeleteLast: Bool = true
    ) {
        self.speakOnTap = speakOnTap
        self.speakOnBarTap = speakOnBarTap
        self.clearAfterSpeak = clearAfterSpeak
        self.style = style
        self.backgroundHex = backgroundHex
        self.textAboveImage = textAboveImage
        self.showDeleteLast = showDeleteLast
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speakOnTap = try container.decodeIfPresent(Bool.self, forKey: .speakOnTap) ?? true
        speakOnBarTap = try container.decodeIfPresent(Bool.self, forKey: .speakOnBarTap) ?? true
        clearAfterSpeak = try container.decodeIfPresent(Bool.self, forKey: .clearAfterSpeak) ?? false
        style = try container.decodeIfPresent(String.self, forKey: .style) ?? "standard"
        backgroundHex = try container.decodeIfPresent(String.self, forKey: .backgroundHex)
        textAboveImage = try container.decodeIfPresent(Bool.self, forKey: .textAboveImage) ?? false
        showDeleteLast = try container.decodeIfPresent(Bool.self, forKey: .showDeleteLast) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(speakOnTap, forKey: .speakOnTap)
        try container.encode(speakOnBarTap, forKey: .speakOnBarTap)
        try container.encode(clearAfterSpeak, forKey: .clearAfterSpeak)
        try container.encode(style, forKey: .style)
        try container.encodeIfPresent(backgroundHex, forKey: .backgroundHex)
        try container.encode(textAboveImage, forKey: .textAboveImage)
        try container.encode(showDeleteLast, forKey: .showDeleteLast)
    }
}
