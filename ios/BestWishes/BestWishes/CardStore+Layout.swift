import Foundation
import UIKit

extension CardStore {
    var currentFolderKey: String { Self.orderKey(folderId: currentFolder?.id) }

    var availableFolderLinks: [(id: String, name: String)] {
        grouping.folders
            .map { ($0.id, displayLabel(for: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func speakText(for card: Card) -> String {
        let overlay = speakOverlays[card.slug]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let overlay, !overlay.isEmpty { return overlay }
        return displayLabel(for: card)
    }

    func speakText(for item: BoardItem) -> String? {
        if case .word(let card) = item { return speakText(for: card) }
        return nil
    }

    func style(for item: BoardItem) -> CellStyle {
        if let saved = styleOverlays[item.id] ?? styleOverlays[editorSlug(item.id)] {
            return saved
        }
        if case .word(let card) = item, let fill = wordClassFill(for: card) {
            return CellStyle(backgroundHex: fill, borderHex: CellStyle.default.borderHex)
        }
        return .default
    }

    func style(forCard slug: String) -> CellStyle {
        if let saved = styleOverlays[slug] { return saved }
        if let card = cards.first(where: { $0.slug == slug }) ?? coreCards.first(where: { $0.slug == slug }),
           let fill = wordClassFill(for: card) {
            return CellStyle(backgroundHex: fill, borderHex: CellStyle.default.borderHex)
        }
        return .default
    }

    /// Fitzgerald-key fill for a word on the default board, or nil when the profile does not
    /// color by word type. Imported boards get their colors once, at import time.
    func wordClassFill(for card: Card) -> String? {
        guard !hasImportedBoard, settings.colorScheme == ProfileSettings.fitzgeraldScheme else { return nil }
        let wordClass = wordClass(for: card)
        return ProfileSettings.stripHash(settings.colors[wordClass.rawValue]) ?? wordClass.defaultHex
    }

    func wordClass(for card: Card) -> WordClass {
        WordClass.guess(for: displayLabel(for: card))
    }

    /// Fixed grid for the open board. Hidden items keep their coordinate.
    /// `rows`/`columns` are the caregiver-configured size; extra rows are added if a
    /// saved position would otherwise fall off the board.
    func slots(rows: Int, columns: Int, editing: Bool) -> [BoardSlot] {
        if let imported = slotsFromImport(rows: rows, columns: columns, editing: editing) {
            return imported
        }
        let columns = max(columns, 1)
        let rows = max(rows, 1)
        var placed = placements(columns: columns)
        let maxRow = placed.values.map(\.row).max() ?? -1
        let displayRows = max(rows, maxRow + 1)
        var occupier: [GridCoord: BoardItem] = [:]
        let visible = Dictionary(uniqueKeysWithValues: currentItems.map { ($0.id, $0) })

        for item in currentItems {
            if let coord = placed[item.id] {
                occupier[coord] = item
            }
        }
        var hiddenAt: [GridCoord: BoardItem] = [:]
        for (itemID, coord) in placed where visible[itemID] == nil {
            if let item = itemForID(itemID), hiddenSlugs.contains(itemSlug(item)) {
                hiddenAt[coord] = item
            }
        }

        var result: [BoardSlot] = []
        result.reserveCapacity(displayRows * columns)
        for row in 0..<displayRows {
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

    func firstEmptyCoord(rows: Int, columns: Int) -> GridCoord? {
        slots(rows: rows, columns: columns, editing: true).first(where: \.isEmpty)?.coord
    }

    func draftForNewButton(at coord: GridCoord) -> ButtonEditorDraft {
        .blank(at: coord)
    }

    func draftForExisting(_ item: BoardItem, at coord: GridCoord) -> ButtonEditorDraft {
        let style = style(for: item)
        switch item {
        case .word(let card):
            return ButtonEditorDraft(
                existingID: item.id,
                coord: coord,
                kind: .word,
                label: displayLabel(for: card),
                speak: speakText(for: card),
                backgroundHex: style.backgroundHex,
                borderHex: style.borderHex,
                imageChoice: .keep,
                currentImage: image(for: card),
                folderLinkID: nil
            )
        case .folder(let folder):
            return ButtonEditorDraft(
                existingID: item.id,
                coord: coord,
                kind: .folder,
                label: displayLabel(for: folder),
                speak: displayLabel(for: folder),
                backgroundHex: style.backgroundHex,
                borderHex: style.borderHex,
                imageChoice: .keep,
                currentImage: image(for: folder),
                folderLinkID: folder.id
            )
        }
    }

    /// Persist label, speak text, colors, optional photo, and the grid coordinate.
    func applyEditorMetadata(_ draft: ButtonEditorDraft, itemID: String) {
        let label = draft.trimmedLabel
        let speak = draft.trimmedSpeak
        setDisplayLabel(label, for: editorSlug(itemID))
        setSpeakText(speak, for: editorSlug(itemID))
        setStyle(CellStyle(backgroundHex: draft.backgroundHex, borderHex: draft.borderHex), for: itemID)
        place(id: itemID, at: draft.coord)
        if case .photo(let image) = draft.imageChoice {
            if cache.saveLocalImage(image, for: editorSlug(itemID)) {
                bumpImage(editorSlug(itemID))
            }
        }
    }

    func setSpeakText(_ raw: String, for slug: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = speakOverlays
        if trimmed.isEmpty {
            next.removeValue(forKey: slug)
        } else {
            next[slug] = trimmed
        }
        speakOverlays = next
        persistSpeak()
    }

    func setStyle(_ style: CellStyle, for itemID: String) {
        var next = styleOverlays
        next[itemID] = style
        styleOverlays = next
        persistStyles()
    }

    func place(id: String, at coord: GridCoord) {
        var folderMap = positionOverlays[currentFolderKey] ?? [:]
        // If another visible item owns this cell, swap so nothing is covered.
        if let other = folderMap.first(where: { $0.key != id && $0.value == coord })?.key,
           let current = folderMap[id] {
            folderMap[other] = current
        }
        folderMap[id] = coord
        var overlays = positionOverlays
        overlays[currentFolderKey] = folderMap
        positionOverlays = overlays
        persistPositions()
    }

    func unhideAtOriginalPosition(_ slug: String) {
        unhide(slug)
        // Position overlay is kept at hide time, so the card returns to the same cell.
    }

    private func placements(columns: Int) -> [String: GridCoord] {
        let key = currentFolderKey
        var map = positionOverlays[key] ?? [:]
        let parentId = currentFolder?.id
        let allItems = membershipItems(parentId: parentId)
        let ordered = Self.applyingOrder(allItems, saved: orderOverlays[key])
        var occupied = Set(map.values)
        var changed = false
        for item in ordered where map[item.id] == nil {
            var index = 0
            var coord = GridCoord.rowMajor(index: index, columns: columns)
            while occupied.contains(coord) {
                index += 1
                coord = GridCoord.rowMajor(index: index, columns: columns)
            }
            map[item.id] = coord
            occupied.insert(coord)
            changed = true
        }
        if changed {
            var overlays = positionOverlays
            overlays[key] = map
            positionOverlays = overlays
            persistPositions()
        }
        return map
    }

    func persistPositions() {
        cache.savePositionOverlays(positionOverlays, for: activeProfile)
    }

    func persistSpeak() {
        cache.saveSpeakOverlays(speakOverlays, for: activeProfile)
    }

    func persistStyles() {
        cache.saveStyleOverlays(styleOverlays, for: activeProfile)
    }

    func persistMessageBar() {
        cache.saveMessageBarSettings(messageBar, for: activeProfile)
    }

    func setMessageBar(_ settings: MessageBarSettings) {
        messageBar = settings
        persistMessageBar()
    }

    private func itemSlug(_ item: BoardItem) -> String {
        switch item {
        case .word(let card): return card.slug
        case .folder(let folder): return folder.id
        }
    }

    func editorSlug(_ itemID: String) -> String {
        if itemID.hasPrefix("folder:") {
            return String(itemID.dropFirst("folder:".count))
        }
        return itemID
    }

    func itemForID(_ itemID: String) -> BoardItem? {
        if itemID.hasPrefix("folder:") {
            let id = String(itemID.dropFirst("folder:".count))
            if let folder = grouping.folder(id: id) { return .folder(folder) }
            return nil
        }
        if let card = cards.first(where: { $0.slug == itemID }) { return .word(card) }
        return nil
    }

    /// "New picture" on an existing server word: the server makes a new original picture
    /// (same URL, new ETag); this device drops its copy, downloads the new one, and redraws.
    @discardableResult
    func regeneratePicture(for slug: String) async -> Bool {
        do {
            let card = try await api.regenerateImage(slug: slug)
            cache.dropImageForRefetch(slug)
            await cache.ensureAssets(for: card, api: api, revalidate: true)
            bumpImage(slug)
            banner = "New picture for “\(displayLabel(for: card))”."
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Create or update a button from the editor sheet. New words may call the backend
    /// (Generate). Photos are written only to the on-device cache.
    @discardableResult
    func saveEditorDraft(_ draft: ButtonEditorDraft) async -> String? {
        errorMessage = nil
        if let existingID = draft.existingID {
            applyEditorMetadata(draft, itemID: existingID)
            if draft.kind == .word, draft.imageChoice == .generate {
                banner = "Making a new picture for “\(draft.trimmedLabel)”…"
                if !hasImportedBoard, cards.contains(where: { $0.slug == existingID }) {
                    await regeneratePicture(for: existingID)
                    return existingID
                }
                if let card = await addWord(draft.trimmedLabel) {
                    applyEditorMetadata(draft, itemID: card.slug)
                    return card.slug
                }
                return existingID
            }
            banner = "Saved “\(draft.trimmedLabel)”."
            return existingID
        }

        if draft.kind == .folder {
            if let link = draft.folderLinkID, let folder = grouping.folder(id: link) {
                applyEditorMetadata(draft, itemID: "folder:\(folder.id)")
                place(id: "folder:\(folder.id)", at: draft.coord)
                banner = "Folder “\(draft.trimmedLabel)” is on the board."
                return "folder:\(folder.id)"
            }
            if let folder = await addFolder(draft.trimmedLabel) {
                let itemID = "folder:\(folder.id)"
                applyEditorMetadata(draft, itemID: itemID)
                return itemID
            }
            return nil
        }

        let shouldGenerate = draft.imageChoice == .generate
        if shouldGenerate {
            guard let card = await addWord(draft.trimmedLabel) else { return nil }
            applyEditorMetadata(draft, itemID: card.slug)
            // addWord places via integrate; pin to the chosen empty cell.
            place(id: card.slug, at: draft.coord)
            return card.slug
        }

        // Photo or text-only: still try the backend so we get a spoken MP3,
        // then overwrite the picture locally when a photo was chosen.
        if let card = await addWord(draft.trimmedLabel) {
            applyEditorMetadata(draft, itemID: card.slug)
            place(id: card.slug, at: draft.coord)
            return card.slug
        }

        // Offline fallback: a local-only card so the cell is still filled.
        let slug = slugify(draft.trimmedLabel)
        let card = Card(word: draft.trimmedLabel, slug: slug, imageURL: "", audioURL: "")
        integrateNewCard(card)
        applyEditorMetadata(draft, itemID: slug)
        place(id: slug, at: draft.coord)
        banner = "“\(draft.trimmedLabel)” is on this device only (offline)."
        return slug
    }

    private func slugify(_ word: String) -> String {
        let lowered = word.lowercased()
        let mapped = lowered.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "-"
        }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "card" : collapsed
    }

}
