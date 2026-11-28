import CryptoKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Everything a caregiver made on this device, in one file: for each profile the imported board,
/// hide / order / label / position / spoken-text / color edits, settings, message bar, grid size,
/// and recents, plus every on-device picture. Format `hopesvoice.backup/v1`.
/// Words that live on the server are not copied; the server keeps them.
nonisolated struct VocabularyBackup: Codable, Equatable, Sendable {
    static let format = "hopesvoice.backup/v1"

    var format: String = VocabularyBackup.format
    var createdAt: Date = Date()
    /// Keyed by `KidProfile.fileKey`.
    var profiles: [String: Profile] = [:]
    /// sha256 → picture bytes. `Profile.doc.images` maps each slug to one of these.
    var pictures: [String: Data] = [:]

    struct Profile: Codable, Equatable, Sendable {
        var doc: SyncDoc
        var settings: ProfileSettings
        var messageBar: MessageBarSettings
        var gridRows: Int?
        var gridColumns: Int?
        var recents: [String]
    }
}

enum BackupError: LocalizedError, Equatable {
    case notABackup
    case missingPicture(String)

    var errorDescription: String? {
        switch self {
        case .notABackup: return "That file is not a Hope's Voice backup."
        case .missingPicture(let slug): return "The backup is damaged: the picture for “\(slug)” is missing."
        }
    }
}

enum VocabularyBackupIO {
    static func make(cache: AssetCache, defaults: UserDefaults = .standard) -> VocabularyBackup {
        var backup = VocabularyBackup()
        for profile in KidProfile.allCases {
            var state = SyncState()
            let doc = SyncPlanner.snapshot(cache, profile, state: &state)
            for slug in doc.images.keys {
                if let sha = doc.images[slug], backup.pictures[sha] == nil,
                   let data = try? Data(contentsOf: cache.imageURL(for: slug)) {
                    backup.pictures[sha] = data
                }
            }
            backup.profiles[profile.fileKey] = .init(
                doc: doc,
                settings: cache.loadProfileSettings(for: profile),
                messageBar: cache.loadMessageBarSettings(for: profile),
                gridRows: defaults.object(forKey: GridLayout.rowsKey(for: profile)) as? Int,
                gridColumns: defaults.object(forKey: GridLayout.columnsKey(for: profile)) as? Int,
                recents: cache.loadRecents(for: profile)
            )
        }
        return backup
    }

    static func encode(_ backup: VocabularyBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(backup)
    }

    /// Decode and check the whole file before anything is written: right format, and every
    /// picture present with the bytes its hash promises.
    static func decode(_ data: Data) throws -> VocabularyBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(VocabularyBackup.self, from: data),
              backup.format == VocabularyBackup.format else {
            throw BackupError.notABackup
        }
        for profile in backup.profiles.values {
            for (slug, sha) in profile.doc.images.sorted(by: { $0.key < $1.key }) {
                guard let bytes = backup.pictures[sha], SyncPlanner.hash(bytes) == sha else {
                    throw BackupError.missingPicture(slug)
                }
            }
            if let board = profile.doc.board {
                guard let raw = SyncPlanner.encodeBoard(board),
                      let document = try? BoardImport.decode(raw),
                      BoardImport.validate(document).isValid else { throw BackupError.notABackup }
            }
        }
        return backup
    }

    /// Write every profile's files. The caller then reloads the active profile into the UI.
    static func writeFiles(_ backup: VocabularyBackup, cache: AssetCache, defaults: UserDefaults = .standard) {
        cache.withoutChangeNotifications {
            for profile in KidProfile.allCases {
                guard let saved = backup.profiles[profile.fileKey] else { continue }
                for (slug, sha) in saved.doc.images {
                    if let bytes = backup.pictures[sha] { cache.writeLocalImageData(bytes, for: slug) }
                }
                if let board = saved.doc.board, let raw = SyncPlanner.encodeBoard(board) {
                    cache.saveImportedBoard(raw, for: profile)
                } else {
                    cache.clearImportedBoard(for: profile)
                }
                SyncPlanner.writeOverlays(saved.doc.overlays, cache: cache, profile: profile)
                cache.saveProfileSettings(saved.settings, for: profile)
                cache.saveMessageBarSettings(saved.messageBar, for: profile)
                cache.saveRecents(saved.recents, for: profile)
                if let rows = saved.gridRows { defaults.set(rows, forKey: GridLayout.rowsKey(for: profile)) }
                if let cols = saved.gridColumns { defaults.set(cols, forKey: GridLayout.columnsKey(for: profile)) }
            }
        }
    }

    static func fileName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "HopesVoice-backup-\(formatter.string(from: date)).json"
    }
}

/// `fileExporter` wrapper around backup bytes.
struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
