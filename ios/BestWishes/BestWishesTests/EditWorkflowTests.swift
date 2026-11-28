import XCTest
@testable import BestWishes

@MainActor
final class EditWorkflowTests: XCTestCase {
    private func card(_ word: String, slug: String? = nil) -> Card {
        let slug = slug ?? word.lowercased()
        return Card(
            word: word,
            slug: slug,
            imageURL: "/v1/cards/\(slug)/image",
            audioURL: "/v1/cards/\(slug)/audio"
        )
    }

    private func makeStore() throws -> CardStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-edit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return CardStore(cache: AssetCache(root: root), player: SpeechPlayer())
    }

    private func seed(_ store: CardStore, words: [String] = ["want", "more", "go"]) {
        store.seedLocalBoard(cards: words.map { card($0) }, folders: [])
    }

    func testBlankDraftCannotSaveUntilItHasALabel() {
        var draft = ButtonEditorDraft.blank(at: GridCoord(row: 1, col: 2))
        XCTAssertTrue(draft.isNew)
        XCTAssertFalse(draft.canSave)
        XCTAssertEqual(draft.kind, .word)
        draft.label = "  juice  "
        XCTAssertEqual(draft.trimmedLabel, "juice")
        XCTAssertTrue(draft.canSave)
        XCTAssertEqual(draft.trimmedSpeak, "juice")
    }

    func testSpokenTextDefaultsToTheLabelUntilCustomized() {
        var draft = ButtonEditorDraft.blank(at: GridCoord(row: 0, col: 0))
        draft.label = "want"
        XCTAssertEqual(draft.trimmedSpeak, "want")
        draft.speak = "I want"
        draft.label = "want more"
        // A customized speak string stays put; empty speak falls back to the label.
        XCTAssertEqual(draft.trimmedSpeak, "I want")
    }

    func testSlotsFillAFixedGridAndKeepEmptyCells() throws {
        let store = try makeStore()
        seed(store, words: ["want", "more"])
        let slots = store.slots(rows: 3, columns: 3, editing: false)
        XCTAssertEqual(slots.count, 9)
        let filled = slots.compactMap { slot -> String? in
            if case .item(let item, _) = slot, case .word(let card) = item { return card.slug }
            return nil
        }
        XCTAssertEqual(Set(filled), ["want", "more"])
        XCTAssertEqual(slots.filter(\.isEmpty).count, 7)
        XCTAssertEqual(slots[0].coord, GridCoord(row: 0, col: 0))
        XCTAssertEqual(slots[8].coord, GridCoord(row: 2, col: 2))
    }

    func testPlacingOnAnEmptyCellPinsTheButtonThere() throws {
        let store = try makeStore()
        seed(store, words: ["want", "more", "go"])
        _ = store.slots(rows: 4, columns: 3, editing: true)
        let target = GridCoord(row: 2, col: 1)
        XCTAssertTrue(store.slots(rows: 4, columns: 3, editing: false).contains { $0.coord == target && $0.isEmpty })

        store.place(id: "go", at: target)

        let slots = store.slots(rows: 4, columns: 3, editing: false)
        guard case .item(let item, let coord) = slots.first(where: { $0.coord == target }) else {
            return XCTFail("expected go at row 2 col 1")
        }
        XCTAssertEqual(coord, target)
        if case .word(let card) = item {
            XCTAssertEqual(card.slug, "go")
        } else {
            XCTFail("expected a word")
        }
        // Other cards stayed in their earlier cells and nothing compacted left.
        let goCount = slots.filter { $0.item?.id == "go" }.count
        XCTAssertEqual(goCount, 1)
    }

    func testHideReservesTheCellSoNeighborsDoNotShift() throws {
        let store = try makeStore()
        seed(store, words: ["want", "more", "go"])
        let before = store.slots(rows: 3, columns: 3, editing: false)
        guard case .item(_, let wantCoord) = before.first(where: { $0.item?.id == "want" }) else {
            return XCTFail("want should be placed")
        }
        let neighborIDs = Dictionary(uniqueKeysWithValues: before.compactMap { slot -> (GridCoord, String)? in
            guard let id = slot.item?.id else { return nil }
            return (slot.coord, id)
        })

        store.hideAfterConfirm("want")

        let kid = store.slots(rows: 3, columns: 3, editing: false)
        XCTAssertTrue(kid.contains { $0.coord == wantCoord && $0.isEmpty })
        XCTAssertFalse(kid.contains { $0.item?.id == "want" })
        for slot in kid {
            if let id = slot.item?.id, id != "want" {
                XCTAssertEqual(neighborIDs[slot.coord], id, "\(id) shifted after hide")
            }
        }

        let editing = store.slots(rows: 3, columns: 3, editing: true)
        guard case .hidden(let hidden, let coord) = editing.first(where: { $0.coord == wantCoord }) else {
            return XCTFail("edit mode should keep the hidden card in its cell")
        }
        XCTAssertEqual(coord, wantCoord)
        XCTAssertEqual(hidden.id, "want")

        store.unhide("want")
        let restored = store.slots(rows: 3, columns: 3, editing: false)
        XCTAssertEqual(restored.first(where: { $0.item?.id == "want" })?.coord, wantCoord)
    }

    func testEditorMetadataPersistsSpeakTextColorsAndPosition() throws {
        let store = try makeStore()
        seed(store, words: ["want"])
        var draft = store.draftForExisting(.word(store.cards[0]), at: GridCoord(row: 1, col: 2))
        draft.label = "I want"
        draft.speak = "I want that"
        draft.backgroundHex = "93C47D"
        draft.borderHex = "1C1A17"
        store.applyEditorMetadata(draft, itemID: "want")

        XCTAssertEqual(store.displayLabel(for: store.cards[0]), "I want")
        XCTAssertEqual(store.speakText(for: store.cards[0]), "I want that")
        XCTAssertEqual(store.style(forCard: "want").backgroundHex, "93C47D")
        let slots = store.slots(rows: 4, columns: 3, editing: false)
        XCTAssertEqual(slots.first(where: { $0.item?.id == "want" })?.coord, GridCoord(row: 1, col: 2))
    }

    func testMessageBarSettingsRoundTripPerProfile() throws {
        let store = try makeStore()
        XCTAssertTrue(store.messageBar.speakOnTap)
        XCTAssertTrue(store.messageBar.speakOnBarTap)
        XCTAssertFalse(store.messageBar.clearAfterSpeak)

        store.setMessageBar(MessageBarSettings(speakOnTap: false, speakOnBarTap: true, clearAfterSpeak: true))
        XCTAssertFalse(store.messageBar.speakOnTap)
        XCTAssertTrue(store.messageBar.clearAfterSpeak)

        store.switchToProfile(.child2)
        XCTAssertEqual(store.messageBar, .default)
        store.switchToProfile(.child1)
        XCTAssertFalse(store.messageBar.speakOnTap)
        XCTAssertTrue(store.messageBar.clearAfterSpeak)
    }

    func testTapDoesNotSpeakWhenSpeakOnTapIsOff() throws {
        let store = try makeStore()
        seed(store, words: ["want"])
        store.setMessageBar(MessageBarSettings(speakOnTap: false, speakOnBarTap: true, clearAfterSpeak: false))
        store.lastSpokenSlug = nil
        store.tap(store.cards[0])
        XCTAssertEqual(store.strip.cards.map(\.slug), ["want"])
        XCTAssertNil(store.lastSpokenSlug)
    }

    func testCustomSpeechIsUsedWhenSpokenTextDiffers() {
        let card = card("want")
        XCTAssertNil(SpeechPlayer.customSpeech(for: card, spokenText: nil))
        XCTAssertNil(SpeechPlayer.customSpeech(for: card, spokenText: "want"))
        XCTAssertNil(SpeechPlayer.customSpeech(for: card, spokenText: "  WANT  "))
        XCTAssertEqual(SpeechPlayer.customSpeech(for: card, spokenText: "I want"), "I want")
    }

    func testFirstEmptyCoordIsTheFirstHoleInRowMajorOrder() throws {
        let store = try makeStore()
        seed(store, words: ["want"])
        store.place(id: "want", at: GridCoord(row: 0, col: 1))
        XCTAssertEqual(store.firstEmptyCoord(rows: 2, columns: 3), GridCoord(row: 0, col: 0))
        store.place(id: "want", at: GridCoord(row: 0, col: 0))
        XCTAssertEqual(store.firstEmptyCoord(rows: 2, columns: 3), GridCoord(row: 0, col: 1))
    }
}
