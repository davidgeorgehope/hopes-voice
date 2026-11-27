import Foundation
import UIKit

extension CardStore {
    /// Load a validated `bestwishes.board/v1` file into this profile, all or nothing.
    /// File images are copied on-device only. The document is not sent to the server.
    func importBoard(from url: URL, rawData: Data? = nil) throws {
        let data = try rawData ?? Data(contentsOf: url)
        let document = try BoardImport.decode(data)
        let report = BoardImport.validate(document)
        guard report.isValid else {
            throw BoardImportError.failed(report.errors)
        }

        let bundle = url.deletingLastPathComponent()
        var fileErrors: [String] = []
        for board in document.boards {
            for cell in board.cells where cell.image?.source == "file" {
                let path = cell.image?.path ?? ""
                if resolveImportImage(path: path, bundle: bundle) == nil {
                    fileErrors.append("Cell “\(cell.id)” is missing image file “\(path)”.")
                }
            }
        }
        if !fileErrors.isEmpty {
            throw BoardImportError.failed(fileErrors)
        }

        // All-or-nothing: mutate only after the file checks pass.
        applyImportedDocument(document, raw: data, bundle: bundle)
    }

    func applyImportedDocument(_ document: BoardImportDocument, raw: Data, bundle: URL?) {
        importedDocument = document
        settings = ProfileSettings.fromImport(document.profile)
        cache.saveImportedBoard(raw, for: activeProfile)
        cache.saveProfileSettings(settings, for: activeProfile)
        messageBar = settings.messageBar
        persistMessageBar()
        applyVoiceSettings()

        hiddenSlugs = []
        var nextCards: [Card] = []
        var nextFolders: [BoardFolder] = []
        var nextPositions: [String: [String: GridCoord]] = [:]
        var nextSpeak: [String: String] = [:]
        var nextStyles: [String: CellStyle] = [:]
        var nextLabels: [String: String] = [:]
        importActions = [:]
        importTargets = [:]
        importAddToMessage = [:]

        for board in document.boards {
            let key = Self.orderKey(folderId: board.id == document.profile.homeBoard ? nil : board.id)
            var folderMap: [String: GridCoord] = [:]
            var memberSlugs: [String] = []

            for cell in board.cells {
                let coord = GridCoord(row: cell.row, col: cell.col)
                let itemID = importItemID(cell)
                folderMap[itemID] = coord
                if let speak = cell.speak, !speak.isEmpty {
                    nextSpeak[editorSlug(itemID)] = speak
                }
                if cell.label.isEmpty == false {
                    nextLabels[editorSlug(itemID)] = cell.label
                }
                nextStyles[itemID] = resolvedStyle(for: cell, settings: settings)
                if cell.hidden {
                    hiddenSlugs.insert(editorSlug(itemID))
                }
                switch cell.type {
                case "folder":
                    importTargets[cell.id] = cell.target ?? ""
                    importAddToMessage[itemID] = BoardImport.folderAddsToMessage(cell, behavior: document.profile.folderBehavior)
                    nextFolders.append(
                        BoardFolder(
                            id: cell.id,
                            name: cell.label,
                            parentId: board.id == document.profile.homeBoard ? nil : board.id,
                            memberSlugs: [],
                            imageURL: nil
                        )
                    )
                case "action":
                    importActions[cell.id] = cell.action ?? ""
                    importAddToMessage[itemID] = false
                    nextCards.append(Card(word: cell.label, slug: cell.id, imageURL: "", audioURL: ""))
                default:
                    importAddToMessage[itemID] = BoardImport.wordAddsToMessage(cell)
                    nextCards.append(Card(word: cell.label, slug: cell.id, imageURL: "", audioURL: ""))
                    memberSlugs.append(cell.id)
                }
                if cell.image?.source == "file", let rel = cell.image?.path, let bundle {
                    if let source = resolveImportImage(path: rel, bundle: bundle) {
                        _ = cache.importLocalImage(from: source, for: editorSlug(itemID))
                        bumpImage(editorSlug(itemID))
                    }
                }
            }
            nextPositions[key] = folderMap
            if board.id != document.profile.homeBoard {
                if let existing = nextFolders.firstIndex(where: { $0.id == board.id }) {
                    nextFolders[existing].memberSlugs = memberSlugs
                } else {
                    nextFolders.append(
                        BoardFolder(
                            id: board.id,
                            name: board.title,
                            parentId: nil,
                            memberSlugs: memberSlugs,
                            imageURL: nil
                        )
                    )
                }
            }
        }

        cards = nextCards
        grouping = BoardGrouping(folders: nextFolders)
        positionOverlays = nextPositions
        speakOverlays = nextSpeak
        styleOverlays = nextStyles
        labelOverlays = nextLabels
        orderOverlays = [:]
        folderPath = []
        strip.clear()
        lastSpokenSlug = nil
        persistSnapshot()
        persistPositions()
        persistSpeak()
        persistStyles()
        persistLabels()
        cache.saveHiddenSlugs(hiddenSlugs, for: activeProfile)
        cache.saveFolderPath(folderPath, for: activeProfile)
    }

    func loadImportedBoardIfPresent() {
        guard let data = cache.loadImportedBoard(for: activeProfile) else {
            importedDocument = nil
            return
        }
        importedDocument = try? BoardImport.decode(data)
        if importedDocument != nil {
            settings = cache.loadProfileSettings(for: activeProfile)
            messageBar = settings.messageBar
            applyVoiceSettings()
            rebuildImportIndexes()
        }
    }

    func updateSettings(_ settings: ProfileSettings) {
        self.settings = settings
        messageBar = settings.messageBar
        persistMessageBar()
        cache.saveProfileSettings(settings, for: activeProfile)
        applyVoiceSettings()
    }

    func clearImportedBoard() {

        importedDocument = nil
        importActions = [:]
        importTargets = [:]
        importAddToMessage = [:]
        cache.clearImportedBoard(for: activeProfile)
        settings = .default
        cache.saveProfileSettings(settings, for: activeProfile)
    }

    var hasImportedBoard: Bool { importedDocument != nil }

    var importedBoardRows: Int? {
        guard let document = importedDocument else { return nil }
        return currentImportedBoard(in: document)?.rows ?? document.profile.grid.rows
    }

    var importedBoardCols: Int? {
        guard let document = importedDocument else { return nil }
        return currentImportedBoard(in: document)?.cols ?? document.profile.grid.cols
    }

    var importedBoardTitle: String? {
        guard let document = importedDocument else { return nil }
        return currentImportedBoard(in: document)?.title
    }

    var importedPageCount: Int {
        guard let rows = importedBoardRows else { return 1 }
        let viewport = max(settings.viewportRows, 1)
        return max(Int(ceil(Double(rows) / Double(viewport))), 1)
    }

    func currentImportedBoard(in document: BoardImportDocument? = nil) -> BoardImportBoard? {
        guard let document = document ?? importedDocument else { return nil }
        let id = folderPath.last ?? document.profile.homeBoard
        return document.boards.first(where: { $0.id == id })
    }

    func importItemID(_ cell: BoardImportCell) -> String {
        switch cell.type {
        case "folder":
            return "folder:\(cell.id)"
        default:
            return cell.id
        }
    }

    func slotsFromImport(rows: Int, columns: Int, editing: Bool) -> [BoardSlot]? {
        guard let document = importedDocument, let board = currentImportedBoard(in: document) else {
            return nil
        }
        let columns = max(columns, board.cols ?? document.profile.grid.cols)
        let rows = max(rows, board.rows ?? document.profile.grid.rows)
        var occupier: [GridCoord: BoardItem] = [:]
        var hiddenAt: [GridCoord: BoardItem] = [:]
        for cell in board.cells {
            let coord = GridCoord(row: cell.row, col: cell.col)
            guard let item = boardItem(from: cell) else { continue }
            if cell.hidden {
                hiddenAt[coord] = item
            } else {
                occupier[coord] = item
            }
        }
        var result: [BoardSlot] = []
        for row in 0..<rows {
            for col in 0..<columns {
                let coord = GridCoord(row: row, col: col)
                if let item = occupier[coord] {
                    result.append(.item(item, coord))
                } else if let item = hiddenAt[coord] {
                    result.append(editing ? .hidden(item, coord) : .empty(coord))
                } else {
                    result.append(.empty(coord))
                }
            }
        }
        return result
    }

    func boardItem(from cell: BoardImportCell) -> BoardItem? {
        switch cell.type {
        case "folder":
            let folder = BoardFolder(id: cell.id, name: cell.label, parentId: folderPath.last, memberSlugs: [])
            return .folder(folder)
        case "action", "word":
            if let card = cards.first(where: { $0.slug == cell.id }) {
                return .word(card)
            }
            return .word(Card(word: cell.label, slug: cell.id, imageURL: "", audioURL: ""))
        default:
            return nil
        }
    }

    func selectImported(_ item: BoardItem) -> Bool {
        guard let document = importedDocument else { return false }
        switch item {
        case .word(let card):
            if let action = importActions[card.slug] {
                performImportAction(action)
                return true
            }
            let add = importAddToMessage[card.slug] ?? true
            if add {
                if messageBar.speakOnTap {
                    tap(card)
                } else {
                    strip.append(card)
                    recordSpoken(slugs: [card.slug])
                }
            } else if messageBar.speakOnTap {
                preview(card)
                recordSpoken(slugs: [card.slug])
            }
            if settings.returnHomeAfterSelection, !isAtRoot {
                goHome()
            }
            return true
        case .folder(let folder):
            let itemID = "folder:\(folder.id)"
            if importAddToMessage[itemID] == true {
                let speak = speakOverlays[folder.id] ?? folder.name
                let chip = Card(word: speak, slug: folder.id, imageURL: "", audioURL: "")
                if messageBar.speakOnTap {
                    tap(chip)
                } else {
                    strip.append(chip)
                }
            }
            let target = importTargets[folder.id] ?? folder.id
            if document.boards.contains(where: { $0.id == target }) {
                if folderPath.last != target {
                    if target == document.profile.homeBoard {
                        goHome()
                    } else {
                        folderPath.append(target)
                        persistFolderPath()
                    }
                }
            }
            return true
        }
    }

    func performImportAction(_ action: String) {
        switch action {
        case "clear":
            clearStrip()
        case "delete-last":
            backspaceStrip()
        case "speak-bar":
            speakStrip()
        case "home":
            goHome()
        case "back":
            goBack()
        default:
            break
        }
    }

    func resolvedStyle(for cell: BoardImportCell, settings: ProfileSettings) -> CellStyle {
        let border = ProfileSettings.stripHash(cell.border) ?? CellStyle.default.borderHex
        let writtenBg = ProfileSettings.stripHash(cell.bg) ?? CellStyle.default.backgroundHex
        switch settings.colorMode {
        case "border":
            // Keep an explicit fill only when the transcription sampled a non-white interior.
            let bg: String
            if writtenBg == "FFFFFF" || writtenBg == "FCFCF7" {
                bg = "FFFFFF"
            } else {
                bg = writtenBg
            }
            return CellStyle(backgroundHex: bg, borderHex: border)
        case "fill":
            return CellStyle(backgroundHex: writtenBg, borderHex: border)
        default:
            return CellStyle(backgroundHex: writtenBg, borderHex: border)
        }
    }

    func resolveImportImage(path: String, bundle: URL) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let relative = trimmed.hasPrefix("./") ? String(trimmed.dropFirst(2)) : trimmed
        let candidates: [URL] = [
            bundle.appendingPathComponent(relative),
            bundle.appendingPathComponent((relative as NSString).lastPathComponent),
            bundle.appendingPathComponent("images").appendingPathComponent((relative as NSString).lastPathComponent),
        ]
        // Also accept a sibling folder that only holds the photos (name withheld from git).
        let siblingPhotos = bundle.deletingLastPathComponent().appendingPathComponent((relative as NSString).lastPathComponent)
        var all = candidates
        if let contents = try? FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil) {
            for dir in contents where dir.hasDirectoryPath {
                all.append(dir.appendingPathComponent((relative as NSString).lastPathComponent))
                all.append(dir.appendingPathComponent(relative))
            }
        }
        all.append(siblingPhotos)
        return all.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private func rebuildImportIndexes() {
        importActions = [:]
        importTargets = [:]
        importAddToMessage = [:]
        guard let document = importedDocument else { return }
        let behavior = document.profile.folderBehavior
        for board in document.boards {
            for cell in board.cells {
                let itemID = importItemID(cell)
                switch cell.type {
                case "folder":
                    importTargets[cell.id] = cell.target ?? ""
                    importAddToMessage[itemID] = BoardImport.folderAddsToMessage(cell, behavior: behavior)
                case "action":
                    importActions[cell.id] = cell.action ?? ""
                    importAddToMessage[itemID] = false
                default:
                    importAddToMessage[itemID] = BoardImport.wordAddsToMessage(cell)
                }
            }
        }
    }
}
