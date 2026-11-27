import Foundation

/// A `bestwishes.board/v1` document. The format is public; a real child's file is not.
struct BoardImportDocument: Equatable, Sendable {
    var format: String
    var source: String?
    var profile: BoardImportProfile
    var boards: [BoardImportBoard]
    /// Unknown top-level fields, preserved as required by the format.
    var extra: [String: JSONValue]
}

struct BoardImportProfile: Equatable, Sendable {
    var displayName: String?
    var homeBoard: String
    var grid: BoardImportGrid
    var voice: BoardImportVoice
    var messageBar: BoardImportMessageBar
    var folderBehavior: BoardImportFolderBehavior
    var colorScheme: String
    var colors: [String: String]
    var coreRow: [String]
    /// Board background, e.g. `#000000`.
    var background: String?
    /// `border` = color the outline only; `fill` = use cell `bg`; `custom` leaves each cell as written.
    var colorMode: String?
    var extra: [String: JSONValue]
}

struct BoardImportGrid: Equatable, Sendable, Codable {
    var rows: Int
    var cols: Int
}

struct BoardImportVoice: Equatable, Sendable, Codable {
    var engine: String
    var voiceId: String
    var rate: Double
    var pitch: Double

    static let `default` = BoardImportVoice(
        engine: "system",
        voiceId: "com.apple.voice.compact.en-US.Samantha",
        rate: 1.0,
        pitch: 1.0
    )
}

struct BoardImportMessageBar: Equatable, Sendable, Codable {
    var enabled: Bool
    var speakOnTap: Bool
    var speakOnBarTap: Bool
    var clearAfterSpeak: Bool
    /// `standard` or `compactBlue` (solid bar, picture under the label, delete-last on the right).
    var style: String?
    var background: String?
    var textAboveImage: Bool?
    var deleteLast: Bool?

    static let `default` = BoardImportMessageBar(
        enabled: true,
        speakOnTap: true,
        speakOnBarTap: true,
        clearAfterSpeak: false,
        style: "standard",
        background: nil,
        textAboveImage: false,
        deleteLast: true
    )
}

struct BoardImportFolderBehavior: Equatable, Sendable, Codable {
    var returnHomeAfterSelection: Bool
    /// Default for folder cells that omit `addToMessage`.
    var addFolderWordToBar: Bool?

    static let `default` = BoardImportFolderBehavior(
        returnHomeAfterSelection: false,
        addFolderWordToBar: nil
    )
}

struct BoardImportBoard: Equatable, Sendable {
    var id: String
    var title: String
    var rows: Int?
    var cols: Int?
    var cells: [BoardImportCell]
    var extra: [String: JSONValue]
}

struct BoardImportCell: Equatable, Sendable {
    var id: String
    var row: Int
    var col: Int
    var type: String
    var label: String
    var speak: String?
    var pos: String?
    var bg: String?
    var border: String?
    var image: BoardImportImage?
    var target: String?
    var action: String?
    var addToMessage: Bool?
    var hidden: Bool
    var extra: [String: JSONValue]
}

struct BoardImportImage: Equatable, Sendable, Codable {
    var source: String
    var prompt: String?
    var path: String?
}

/// Validation result. On failure, `errors` is a complete list and the document must not be applied.
struct BoardImportReport: Equatable, Sendable {
    var errors: [String]

    var isValid: Bool { errors.isEmpty }

    static let ok = BoardImportReport(errors: [])
}

enum BoardImportError: LocalizedError, Equatable {
    case unreadable(String)
    case invalidJSON
    case failed([String])

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return "Could not read “\(name)”."
        case .invalidJSON:
            return "That file is not valid JSON."
        case .failed(let errors):
            return errors.joined(separator: "\n")
        }
    }
}

enum BoardImport {
    static let formatVersion = "bestwishes.board/v1"
    static let allowedTypes: Set<String> = ["word", "folder", "action"]
    static let allowedActions: Set<String> = ["back", "home", "clear", "delete-last", "speak-bar"]
    static let allowedImageSources: Set<String> = ["generate", "file", "none"]

    /// Decode a document, folding unknown keys into `extra` at each level.
    static func decode(_ data: Data) throws -> BoardImportDocument {
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw BoardImportError.invalidJSON
        }
        return try parseDocument(object)
    }

    static func decode(from url: URL) throws -> BoardImportDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BoardImportError.unreadable(url.lastPathComponent)
        }
        do {
            return try decode(data)
        } catch let error as BoardImportError {
            throw error
        } catch {
            throw BoardImportError.invalidJSON
        }
    }

    /// All-or-nothing validation as specified in `docs/IMPORT_FORMAT.md`.
    static func validate(_ document: BoardImportDocument) -> BoardImportReport {
        var errors: [String] = []

        if document.format != formatVersion {
            errors.append("format must be “\(formatVersion)” (got “\(document.format)”).")
        }

        if document.profile.homeBoard.isEmpty {
            errors.append("profile.homeBoard is required.")
        }
        if document.profile.grid.rows < 1 {
            errors.append("profile.grid.rows must be at least 1.")
        }
        if document.profile.grid.cols < 1 {
            errors.append("profile.grid.cols must be at least 1.")
        }

        if document.boards.isEmpty {
            errors.append("boards must contain at least one board.")
        }

        var boardIDs = Set<String>()
        for board in document.boards {
            if board.id.isEmpty {
                errors.append("A board is missing an id.")
                continue
            }
            if !boardIDs.insert(board.id).inserted {
                errors.append("Duplicate board id “\(board.id)”.")
            }
        }

        let knownBoards = boardIDs
        if !document.profile.homeBoard.isEmpty, !knownBoards.contains(document.profile.homeBoard) {
            errors.append("profile.homeBoard “\(document.profile.homeBoard)” does not match any board id.")
        }

        var cellIDs = Set<String>()
        for board in document.boards {
            let rows = board.rows ?? document.profile.grid.rows
            let cols = board.cols ?? document.profile.grid.cols
            if rows < 1 || cols < 1 {
                errors.append("Board “\(board.id)” has an invalid grid size (\(rows)×\(cols)).")
            }
            var positions = Set<BoardImportIndex>()
            for cell in board.cells {
                if cell.id.isEmpty {
                    errors.append("Board “\(board.id)” has a cell with no id.")
                } else if !cellIDs.insert(cell.id).inserted {
                    errors.append("Duplicate cell id “\(cell.id)”.")
                }
                if cell.row < 0 || cell.col < 0 || cell.row >= rows || cell.col >= cols {
                    errors.append(
                        "Cell “\(cell.id)” at \(cell.row),\(cell.col) does not fit board “\(board.id)” (\(rows)×\(cols))."
                    )
                }
                let pos = BoardImportIndex(row: cell.row, col: cell.col)
                if !positions.insert(pos).inserted {
                    errors.append(
                        "Board “\(board.id)” has two cells at row \(cell.row), column \(cell.col)."
                    )
                }
                if !allowedTypes.contains(cell.type) {
                    errors.append("Cell “\(cell.id)” has unknown type “\(cell.type)”.")
                }
                if cell.type == "folder" {
                    if let target = cell.target, !target.isEmpty {
                        if !knownBoards.contains(target) {
                            errors.append("Cell “\(cell.id)” targets missing board “\(target)”.")
                        }
                    } else {
                        errors.append("Folder cell “\(cell.id)” is missing a target.")
                    }
                }
                if cell.type == "action" {
                    if let action = cell.action, !action.isEmpty {
                        if !allowedActions.contains(action) {
                            errors.append("Cell “\(cell.id)” has unknown action “\(action)”.")
                        }
                    } else {
                        errors.append("Action cell “\(cell.id)” is missing an action.")
                    }
                }
                if let image = cell.image, !allowedImageSources.contains(image.source) {
                    errors.append("Cell “\(cell.id)” has unknown image.source “\(image.source)”.")
                }
                if cell.image?.source == "file" {
                    let path = cell.image?.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if path.isEmpty {
                        errors.append("Cell “\(cell.id)” has image.source “file” but no path.")
                    }
                }
            }
        }

        return BoardImportReport(errors: errors)
    }

    /// True when this folder cell should also append its word to the message bar.
    static func folderAddsToMessage(_ cell: BoardImportCell, behavior: BoardImportFolderBehavior) -> Bool {
        if let flagged = cell.addToMessage { return flagged }
        if let global = behavior.addFolderWordToBar { return global }
        if let speak = cell.speak, !speak.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        // P2G grammar folders often carry a word class in extra; category folders do not.
        if let raw = cell.extra["p2gWordClass"], raw.isPresent {
            return true
        }
        return false
    }

    static func wordAddsToMessage(_ cell: BoardImportCell) -> Bool {
        cell.addToMessage ?? true
    }
}

private struct BoardImportIndex: Hashable {
    var row: Int
    var col: Int
}

// MARK: - Parsing (unknown keys → extra)

private let documentKnown: Set<String> = ["format", "source", "profile", "boards", "extra"]
private let profileKnown: Set<String> = [
    "displayName", "homeBoard", "grid", "voice", "messageBar", "folderBehavior",
    "colorScheme", "colors", "coreRow", "background", "colorMode", "extra",
]
private let boardKnown: Set<String> = ["id", "title", "rows", "cols", "cells", "extra"]
private let cellKnown: Set<String> = [
    "id", "row", "col", "type", "label", "speak", "pos", "bg", "border",
    "image", "target", "action", "addToMessage", "hidden", "extra",
]

private func parseDocument(_ object: [String: Any]) throws -> BoardImportDocument {
    let format = object["format"] as? String ?? ""
    let source = object["source"] as? String
    let profileRaw = object["profile"] as? [String: Any] ?? [:]
    let boardsRaw = object["boards"] as? [[String: Any]] ?? []
    var extra = JSONValue.dictionary(from: object, excluding: documentKnown)
    if let explicit = object["extra"] as? [String: Any] {
        extra.merge(JSONValue.dictionary(from: explicit, excluding: [])) { _, new in new }
    }
    return BoardImportDocument(
        format: format,
        source: source,
        profile: parseProfile(profileRaw),
        boards: boardsRaw.map(parseBoard),
        extra: extra
    )
}

private func parseProfile(_ object: [String: Any]) -> BoardImportProfile {
    let gridRaw = object["grid"] as? [String: Any] ?? [:]
    let voiceRaw = object["voice"] as? [String: Any] ?? [:]
    let barRaw = object["messageBar"] as? [String: Any] ?? [:]
    let folderRaw = object["folderBehavior"] as? [String: Any] ?? [:]
    let colorsRaw = object["colors"] as? [String: Any] ?? [:]
    var colors: [String: String] = [:]
    for (key, value) in colorsRaw {
        if let string = value as? String { colors[key] = string }
    }
    let core = (object["coreRow"] as? [Any] ?? []).compactMap { $0 as? String }
    var extra = JSONValue.dictionary(from: object, excluding: profileKnown)
    if let explicit = object["extra"] as? [String: Any] {
        extra.merge(JSONValue.dictionary(from: explicit, excluding: [])) { _, new in new }
    }
    let defaultVoice = BoardImportVoice.default
    let defaultBar = BoardImportMessageBar.default
    let defaultFolder = BoardImportFolderBehavior.default
    return BoardImportProfile(
        displayName: object["displayName"] as? String,
        homeBoard: object["homeBoard"] as? String ?? "home",
        grid: BoardImportGrid(
            rows: intValue(gridRaw["rows"]) ?? 4,
            cols: intValue(gridRaw["cols"]) ?? 6
        ),
        voice: BoardImportVoice(
            engine: voiceRaw["engine"] as? String ?? defaultVoice.engine,
            voiceId: voiceRaw["voiceId"] as? String ?? defaultVoice.voiceId,
            rate: doubleValue(voiceRaw["rate"]) ?? defaultVoice.rate,
            pitch: doubleValue(voiceRaw["pitch"]) ?? defaultVoice.pitch
        ),
        messageBar: BoardImportMessageBar(
            enabled: boolValue(barRaw["enabled"]) ?? defaultBar.enabled,
            speakOnTap: boolValue(barRaw["speakOnTap"]) ?? defaultBar.speakOnTap,
            speakOnBarTap: boolValue(barRaw["speakOnBarTap"]) ?? defaultBar.speakOnBarTap,
            clearAfterSpeak: boolValue(barRaw["clearAfterSpeak"]) ?? defaultBar.clearAfterSpeak,
            style: barRaw["style"] as? String,
            background: barRaw["background"] as? String,
            textAboveImage: boolValue(barRaw["textAboveImage"]),
            deleteLast: boolValue(barRaw["deleteLast"])
        ),
        folderBehavior: BoardImportFolderBehavior(
            returnHomeAfterSelection: boolValue(folderRaw["returnHomeAfterSelection"]) ?? defaultFolder.returnHomeAfterSelection,
            addFolderWordToBar: boolValue(folderRaw["addFolderWordToBar"])
        ),
        colorScheme: object["colorScheme"] as? String ?? "custom",
        colors: colors,
        coreRow: core,
        background: object["background"] as? String,
        colorMode: object["colorMode"] as? String,
        extra: extra
    )
}

private func parseBoard(_ object: [String: Any]) -> BoardImportBoard {
    let cells = (object["cells"] as? [[String: Any]] ?? []).map(parseCell)
    var extra = JSONValue.dictionary(from: object, excluding: boardKnown)
    if let explicit = object["extra"] as? [String: Any] {
        extra.merge(JSONValue.dictionary(from: explicit, excluding: [])) { _, new in new }
    }
    return BoardImportBoard(
        id: object["id"] as? String ?? "",
        title: object["title"] as? String ?? (object["id"] as? String ?? ""),
        rows: intValue(object["rows"]),
        cols: intValue(object["cols"]),
        cells: cells,
        extra: extra
    )
}

private func parseCell(_ object: [String: Any]) -> BoardImportCell {
    var extra = JSONValue.dictionary(from: object, excluding: cellKnown)
    if let explicit = object["extra"] as? [String: Any] {
        extra.merge(JSONValue.dictionary(from: explicit, excluding: [])) { _, new in new }
    }
    let imageRaw = object["image"] as? [String: Any]
    let image: BoardImportImage? = imageRaw.map {
        BoardImportImage(
            source: $0["source"] as? String ?? "generate",
            prompt: $0["prompt"] as? String,
            path: $0["path"] as? String
        )
    }
    return BoardImportCell(
        id: object["id"] as? String ?? "",
        row: intValue(object["row"]) ?? 0,
        col: intValue(object["col"]) ?? 0,
        type: object["type"] as? String ?? "word",
        label: object["label"] as? String ?? "",
        speak: object["speak"] as? String,
        pos: object["pos"] as? String,
        bg: object["bg"] as? String,
        border: object["border"] as? String,
        image: image,
        target: object["target"] as? String,
        action: object["action"] as? String,
        addToMessage: boolValue(object["addToMessage"]),
        hidden: boolValue(object["hidden"]) ?? false,
        extra: extra
    )
}

private func intValue(_ raw: Any?) -> Int? {
    if let value = raw as? Int { return value }
    if let value = raw as? Double { return Int(value) }
    if let value = raw as? NSNumber { return value.intValue }
    if let value = raw as? String { return Int(value) }
    return nil
}

private func doubleValue(_ raw: Any?) -> Double? {
    if let value = raw as? Double { return value }
    if let value = raw as? Int { return Double(value) }
    if let value = raw as? NSNumber { return value.doubleValue }
    if let value = raw as? String { return Double(value) }
    return nil
}

private func boolValue(_ raw: Any?) -> Bool? {
    if let value = raw as? Bool { return value }
    if let value = raw as? Int { return value != 0 }
    if let value = raw as? NSNumber { return value.boolValue }
    if let value = raw as? String {
        switch value.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }
    return nil
}

/// JSON tree used to preserve unknown import fields.
enum JSONValue: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    var isPresent: Bool {
        switch self {
        case .null: return false
        default: return true
        }
    }

    static func from(_ raw: Any) -> JSONValue? {
        switch raw {
        case is NSNull:
            return .null
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .int(value)
        case let value as Double:
            return value.rounded() == value ? .int(Int(value)) : .double(value)
        case let value as NSNumber:
            // Bool is a NSNumber in some JSON paths; detect it.
            let obj = value as CFTypeRef
            if CFGetTypeID(obj) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            if value.doubleValue.rounded() == value.doubleValue {
                return .int(value.intValue)
            }
            return .double(value.doubleValue)
        case let value as String:
            return .string(value)
        case let value as [Any]:
            return .array(value.compactMap(JSONValue.from))
        case let value as [String: Any]:
            var object: [String: JSONValue] = [:]
            for (key, item) in value {
                if let parsed = JSONValue.from(item) { object[key] = parsed }
            }
            return .object(object)
        default:
            return nil
        }
    }

    static func dictionary(from object: [String: Any], excluding known: Set<String>) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for (key, value) in object where !known.contains(key) {
            if let parsed = JSONValue.from(value) {
                result[key] = parsed
            }
        }
        return result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
