import Foundation

/// Per-profile look and behavior. Loaded from an import or the caregiver Settings sheet.
struct ProfileSettings: Equatable, Codable, Sendable {
    var homeBoard: String
    /// Visible rows in one page. A taller board pages (or scrolls) in this step.
    var viewportRows: Int
    var viewportCols: Int
    var voice: BoardImportVoice
    var messageBar: MessageBarSettings
    var returnHomeAfterSelection: Bool
    var addFolderWordToBar: Bool?
    var colorScheme: String
    var colors: [String: String]
    /// Board background, `#RRGGBB`.
    var backgroundHex: String
    /// `border`, `fill`, or `custom` (use each cell's written bg and border).
    var colorMode: String
    var showCoreRow: Bool
    var showRecents: Bool

    static let fitzgeraldScheme = "fitzgerald"

    static let `default` = ProfileSettings(
        homeBoard: "home",
        viewportRows: 4,
        viewportCols: 6,
        voice: .default,
        messageBar: .default,
        returnHomeAfterSelection: false,
        addFolderWordToBar: nil,
        colorScheme: fitzgeraldScheme,
        colors: [:],
        backgroundHex: "E8DBC2",
        colorMode: "custom",
        showCoreRow: true,
        showRecents: true
    )

    static func fromImport(_ profile: BoardImportProfile) -> ProfileSettings {
        var style = profile.messageBar.style ?? "standard"
        if profile.messageBar.style == nil, Self.looksLikeCompactBlueBar(profile) {
            style = "compactBlue"
        }
        var bar = MessageBarSettings(
            speakOnTap: profile.messageBar.speakOnTap,
            speakOnBarTap: profile.messageBar.speakOnBarTap,
            clearAfterSpeak: profile.messageBar.clearAfterSpeak,
            style: style,
            backgroundHex: Self.stripHash(profile.messageBar.background),
            textAboveImage: profile.messageBar.textAboveImage ?? (style == "compactBlue"),
            showDeleteLast: profile.messageBar.deleteLast ?? true
        )
        if bar.style == "compactBlue" {
            if bar.backgroundHex == nil { bar.backgroundHex = "0000CB" }
            if profile.messageBar.textAboveImage == nil { bar.textAboveImage = true }
        }
        let background = Self.stripHash(profile.background)
            ?? (profile.extra["backgroundColor"].flatMap(Self.colorNameToHex) ?? "E8DBC2")
        let colorMode = profile.colorMode
            ?? (boolFromExtra(profile.extra["colorCodeBackground"]) == false && boolFromExtra(profile.extra["colorCodeBorder"]) == true
                ? "border"
                : "custom")
        let showChrome = profile.coreRow.isEmpty == false
        return ProfileSettings(
            homeBoard: profile.homeBoard,
            viewportRows: max(profile.grid.rows, 1),
            viewportCols: max(profile.grid.cols, 1),
            voice: Self.resolvedVoice(profile.voice),
            messageBar: bar,
            returnHomeAfterSelection: profile.folderBehavior.returnHomeAfterSelection,
            addFolderWordToBar: profile.folderBehavior.addFolderWordToBar,
            colorScheme: profile.colorScheme,
            colors: profile.colors,
            backgroundHex: background,
            colorMode: colorMode,
            showCoreRow: showChrome,
            // Most AAC boards have no Recents row, so an imported board starts without one.
            // A caregiver can turn it on in Edit → Settings → Show recents.
            showRecents: false
        )
    }

    /// Stand-in for proprietary voices (for example Acapela) that we cannot ship.
    static func resolvedVoice(_ voice: BoardImportVoice) -> BoardImportVoice {
        var resolved = voice
        if resolved.engine == "system", !resolved.voiceId.hasPrefix("com.apple.") {
            resolved.voiceId = "com.apple.voice.compact.en-US.Samantha"
        }
        return resolved
    }

    /// Infer the compact blue bar when the file describes it but omits `style`.
    static func looksLikeCompactBlueBar(_ profile: BoardImportProfile) -> Bool {
        if let background = stripHash(profile.messageBar.background), background == "0000CB" {
            return true
        }
        if case .string(let look) = profile.extra["messageBarLook"] {
            let lowered = look.lowercased()
            if lowered.contains("0000cb") || lowered.contains("delete") { return true }
        }
        if boolFromExtra(profile.extra["textBelowImages"]) == false {
            return true
        }
        return false
    }

    static func stripHash(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("#") { value.removeFirst() }
        return value.uppercased()
    }

    private static func colorNameToHex(_ value: JSONValue?) -> String? {
        guard case .string(let name) = value else { return nil }
        switch name.lowercased() {
        case "black": return "000000"
        case "white": return "FFFFFF"
        default: return stripHash(name)
        }
    }

    private static func boolFromExtra(_ value: JSONValue?) -> Bool? {
        switch value {
        case .bool(let flag): return flag
        case .int(let number): return number != 0
        case .string(let text):
            switch text.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        default: return nil
        }
    }
}
