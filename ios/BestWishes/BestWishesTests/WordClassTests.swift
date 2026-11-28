import XCTest
@testable import BestWishes

@MainActor
final class WordClassTests: XCTestCase {
    private func makeStore() throws -> CardStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-wordclass-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return CardStore(api: APIClient(baseURL: APIClient.unreachableBaseURL), cache: AssetCache(root: root), player: SpeechPlayer())
    }

    private func card(_ word: String) -> Card {
        let slug = word.lowercased().replacingOccurrences(of: " ", with: "-")
        return Card(word: word, slug: slug, imageURL: "/v1/cards/\(slug)/image", audioURL: "/v1/cards/\(slug)/audio")
    }

    func testCoreWordsGetTheirFitzgeraldClass() {
        XCTAssertEqual(WordClass.guess(for: "I"), .pronoun)
        XCTAssertEqual(WordClass.guess(for: "Mommy"), .pronoun)
        XCTAssertEqual(WordClass.guess(for: "want"), .verb)
        XCTAssertEqual(WordClass.guess(for: "go"), .verb)
        XCTAssertEqual(WordClass.guess(for: "help"), .verb)
        XCTAssertEqual(WordClass.guess(for: "more"), .adjective)
        XCTAssertEqual(WordClass.guess(for: "stop"), .negation)
        XCTAssertEqual(WordClass.guess(for: "please"), .social)
        XCTAssertEqual(WordClass.guess(for: "where"), .question)
        XCTAssertEqual(WordClass.guess(for: "juice"), .noun, "unknown words are things")
    }

    func testImportNamesAndSynonyms() {
        XCTAssertEqual(WordClass(importName: "verb"), .verb)
        XCTAssertEqual(WordClass(importName: " ADJ "), .adjective)
        XCTAssertEqual(WordClass(importName: "people"), .pronoun)
        XCTAssertNil(WordClass(importName: "gibberish"))
        XCTAssertNil(WordClass(importName: nil))
    }

    func testDefaultBoardColorsByWordTypeUnlessTurnedOff() throws {
        let store = try makeStore()
        let want = card("want"), juice = card("juice"), me = card("I")
        store.seedLocalBoard(cards: [want, juice, me], folders: [])
        XCTAssertEqual(store.settings.colorScheme, ProfileSettings.fitzgeraldScheme, "new profiles color by word type")
        XCTAssertEqual(store.style(for: .word(want)).backgroundHex, WordClass.verb.defaultHex)
        XCTAssertEqual(store.style(for: .word(juice)).backgroundHex, WordClass.noun.defaultHex)
        XCTAssertEqual(store.style(forCard: me.slug).backgroundHex, WordClass.pronoun.defaultHex)

        var settings = store.settings
        settings.colorScheme = "custom"
        store.updateSettings(settings)
        XCTAssertEqual(store.style(for: .word(want)), .default)
    }

    func testCustomPaletteAndCaregiverColorWin() throws {
        let store = try makeStore()
        let want = card("want"), juice = card("juice")
        store.seedLocalBoard(cards: [want, juice], folders: [])
        var settings = store.settings
        settings.colors = ["verb": "#00FF00"]
        store.updateSettings(settings)
        XCTAssertEqual(store.style(for: .word(want)).backgroundHex, "00FF00")

        let picked = CellStyle(backgroundHex: "123456", borderHex: "000000")
        store.setStyle(picked, for: juice.slug)
        XCTAssertEqual(store.style(for: .word(juice)), picked)
    }

    func testFitzgeraldImportFillsCellsWithoutAnExplicitColor() throws {
        let store = try makeStore()
        var settings = ProfileSettings.default
        settings.colorScheme = ProfileSettings.fitzgeraldScheme
        settings.colorMode = "fill"
        settings.colors = ["noun": "#FFAA00"]
        func cell(_ label: String, pos: String?, bg: String? = nil) throws -> BoardImportCell {
            var object: [String: Any] = ["id": label, "row": 0, "col": 0, "type": "word", "label": label]
            if let pos { object["pos"] = pos }
            if let bg { object["bg"] = bg }
            let data = try JSONSerialization.data(withJSONObject: [
                "format": BoardImport.formatVersion,
                "profile": ["homeBoard": "home", "grid": ["rows": 1, "cols": 1]],
                "boards": [["id": "home", "title": "Home", "cells": [object]]],
            ])
            return try XCTUnwrap(BoardImport.decode(data).boards.first?.cells.first)
        }
        XCTAssertEqual(store.resolvedStyle(for: try cell("eat", pos: "verb"), settings: settings).backgroundHex, WordClass.verb.defaultHex)
        XCTAssertEqual(store.resolvedStyle(for: try cell("ball", pos: "noun"), settings: settings).backgroundHex, "FFAA00")
        XCTAssertEqual(store.resolvedStyle(for: try cell("I", pos: nil), settings: settings).backgroundHex, WordClass.pronoun.defaultHex)
        XCTAssertEqual(store.resolvedStyle(for: try cell("eat", pos: "verb", bg: "#ABCDEF"), settings: settings).backgroundHex, "ABCDEF")
        settings.colorScheme = "custom"
        XCTAssertEqual(store.resolvedStyle(for: try cell("eat", pos: "verb"), settings: settings).backgroundHex, CellStyle.default.backgroundHex)
    }
}
