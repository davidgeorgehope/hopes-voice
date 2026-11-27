import XCTest
@testable import BestWishes

final class BoardImportTests: XCTestCase {
    private func sampleURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.board.json")
    }

    private func sampleData() throws -> Data {
        try Data(contentsOf: sampleURL())
    }

    private func sample() throws -> BoardImportDocument {
        try BoardImport.decode(from: sampleURL())
    }

    func testSampleFixtureIsValidAndLoadsExpectedBoards() throws {
        let document = try sample()
        let report = BoardImport.validate(document)
        XCTAssertEqual(report.errors, [])
        XCTAssertTrue(report.isValid)
        XCTAssertEqual(document.format, BoardImport.formatVersion)
        XCTAssertEqual(document.profile.displayName, "Child 1")
        XCTAssertEqual(document.profile.homeBoard, "home")
        XCTAssertEqual(document.profile.grid.rows, 4)
        XCTAssertEqual(document.profile.grid.cols, 6)
        XCTAssertEqual(document.profile.messageBar.style, "compactBlue")
        XCTAssertEqual(document.profile.messageBar.background, "#0000CB")
        XCTAssertEqual(document.profile.background, "#000000")
        XCTAssertEqual(document.profile.colorMode, "border")
        XCTAssertTrue(document.profile.folderBehavior.returnHomeAfterSelection)
        XCTAssertEqual(document.boards.map(\.id), ["home", "food"])
        XCTAssertEqual(document.boards[0].rows, 6)
        XCTAssertEqual(document.boards[0].cells.count, 4)
        XCTAssertEqual(document.boards[0].cells[0].id, "want")
        XCTAssertEqual(document.boards[0].cells[0].type, "folder")
        XCTAssertEqual(document.boards[0].cells[0].target, "food")
        XCTAssertEqual(document.boards[0].cells[0].addToMessage, true)
        XCTAssertEqual(document.boards[1].cells[0].id, "water")
        XCTAssertEqual(document.boards[1].cells[0].row, 0)
        XCTAssertEqual(document.boards[1].cells[0].col, 1)
    }

    func testUnknownFieldsArePreservedInExtra() throws {
        let document = try sample()
        XCTAssertEqual(document.extra["transcriptNote"], .string("public sample — no family data"))
    }

    func testWrongFormatIsRejected() throws {
        var object = try JSONSerialization.jsonObject(with: sampleData()) as! [String: Any]
        object["format"] = "bestwishes.board/v0"
        let data = try JSONSerialization.data(withJSONObject: object)
        let document = try BoardImport.decode(data)
        let report = BoardImport.validate(document)
        XCTAssertTrue(report.errors.contains { $0.contains("format must be") })
    }

    func testDuplicateCellIdsAreListed() throws {
        var object = try JSONSerialization.jsonObject(with: sampleData()) as! [String: Any]
        var boards = object["boards"] as! [[String: Any]]
        var cells = boards[1]["cells"] as! [[String: Any]]
        cells[0]["id"] = "help"
        boards[1]["cells"] = cells
        object["boards"] = boards
        let document = try BoardImport.decode(JSONSerialization.data(withJSONObject: object))
        let report = BoardImport.validate(document)
        XCTAssertTrue(report.errors.contains { $0.contains("Duplicate cell id") && $0.contains("help") })
        XCTAssertFalse(report.isValid)
    }

    func testOverlappingPositionsAreListed() throws {
        var object = try JSONSerialization.jsonObject(with: sampleData()) as! [String: Any]
        var boards = object["boards"] as! [[String: Any]]
        var cells = boards[0]["cells"] as! [[String: Any]]
        var copy = cells[0]
        copy["id"] = "want-copy"
        cells.append(copy)
        boards[0]["cells"] = cells
        object["boards"] = boards
        let document = try BoardImport.decode(JSONSerialization.data(withJSONObject: object))
        let report = BoardImport.validate(document)
        XCTAssertTrue(report.errors.contains { $0.contains("two cells at row 0, column 0") })
    }

    func testMissingFolderTargetIsListed() throws {
        var object = try JSONSerialization.jsonObject(with: sampleData()) as! [String: Any]
        var boards = object["boards"] as! [[String: Any]]
        var cells = boards[0]["cells"] as! [[String: Any]]
        cells[0]["target"] = "missing-board"
        boards[0]["cells"] = cells
        object["boards"] = boards
        let document = try BoardImport.decode(JSONSerialization.data(withJSONObject: object))
        let report = BoardImport.validate(document)
        XCTAssertTrue(report.errors.contains { $0.contains("missing board") && $0.contains("missing-board") })
    }

    func testCellOutsideGridIsListed() throws {
        var object = try JSONSerialization.jsonObject(with: sampleData()) as! [String: Any]
        var boards = object["boards"] as! [[String: Any]]
        var cells = boards[0]["cells"] as! [[String: Any]]
        cells[0]["row"] = 99
        boards[0]["cells"] = cells
        object["boards"] = boards
        let document = try BoardImport.decode(JSONSerialization.data(withJSONObject: object))
        let report = BoardImport.validate(document)
        XCTAssertTrue(report.errors.contains { $0.contains("does not fit board") })
    }

    func testInvalidFileCollectsEveryErrorAndIsNotValid() throws {
        var object = try JSONSerialization.jsonObject(with: sampleData()) as! [String: Any]
        var boards = object["boards"] as! [[String: Any]]
        var homeCells = boards[0]["cells"] as! [[String: Any]]
        homeCells[0]["target"] = "missing-board"
        homeCells[1]["id"] = "want"
        boards[0]["cells"] = homeCells
        var foodCells = boards[1]["cells"] as! [[String: Any]]
        foodCells[0]["row"] = 40
        boards[1]["cells"] = foodCells
        object["boards"] = boards
        let document = try BoardImport.decode(JSONSerialization.data(withJSONObject: object))
        let report = BoardImport.validate(document)
        XCTAssertGreaterThanOrEqual(report.errors.count, 3)
        XCTAssertFalse(report.isValid)
    }

    func testFolderAddToMessageHonorsFlagAndWordClass() {
        let flagged = BoardImportCell(
            id: "want", row: 0, col: 0, type: "folder", label: "I want",
            speak: nil, pos: nil, bg: nil, border: nil, image: nil,
            target: "food", action: nil, addToMessage: true, hidden: false, extra: [:]
        )
        let category = BoardImportCell(
            id: "people", row: 0, col: 1, type: "folder", label: "People",
            speak: nil, pos: nil, bg: nil, border: nil, image: nil,
            target: "people", action: nil, addToMessage: nil, hidden: false, extra: [:]
        )
        let grammar = BoardImportCell(
            id: "i", row: 0, col: 2, type: "folder", label: "I",
            speak: nil, pos: nil, bg: nil, border: nil, image: nil,
            target: "i", action: nil, addToMessage: nil, hidden: false,
            extra: ["p2gWordClass": .int(0)]
        )
        let behavior = BoardImportFolderBehavior.default
        XCTAssertTrue(BoardImport.folderAddsToMessage(flagged, behavior: behavior))
        XCTAssertFalse(BoardImport.folderAddsToMessage(category, behavior: behavior))
        XCTAssertTrue(BoardImport.folderAddsToMessage(grammar, behavior: behavior))
        XCTAssertTrue(BoardImport.wordAddsToMessage(BoardImportCell(
            id: "help", row: 0, col: 3, type: "word", label: "help",
            speak: nil, pos: nil, bg: nil, border: nil, image: nil,
            target: nil, action: nil, addToMessage: nil, hidden: false, extra: [:]
        )))
    }

    @MainActor
    func testImportingTheSamplePlacesCellsAndAppliesSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = CardStore(cache: AssetCache(root: root), player: SpeechPlayer())

        try store.importBoard(from: sampleURL())

        XCTAssertTrue(store.hasImportedBoard)
        XCTAssertEqual(store.settings.viewportRows, 4)
        XCTAssertEqual(store.settings.viewportCols, 6)
        XCTAssertEqual(store.settings.backgroundHex, "000000")
        XCTAssertEqual(store.settings.colorMode, "border")
        XCTAssertEqual(store.messageBar.style, "compactBlue")
        XCTAssertEqual(store.messageBar.backgroundHex, "0000CB")
        XCTAssertTrue(store.settings.returnHomeAfterSelection)
        XCTAssertFalse(store.settings.showCoreRow)
        XCTAssertEqual(store.importedBoardRows, 6)
        XCTAssertEqual(store.importedPageCount, 2)

        let slots = store.slots(rows: 6, columns: 6, editing: false)
        XCTAssertEqual(slots.count, 36)
        XCTAssertEqual(slots.first(where: { $0.coord == GridCoord(row: 0, col: 0) })?.item?.id, "folder:want")
        XCTAssertEqual(slots.first(where: { $0.coord == GridCoord(row: 0, col: 1) })?.item?.id, "help")
        XCTAssertTrue(slots.contains { $0.coord == GridCoord(row: 0, col: 2) && $0.isEmpty })
        XCTAssertEqual(slots.first(where: { $0.coord == GridCoord(row: 3, col: 0) })?.item?.id, "clear")
        // Two folder buttons can share a target without stealing each other's seats.
        XCTAssertEqual(slots.first(where: { $0.coord == GridCoord(row: 1, col: 2) })?.item?.id, "folder:things")
    }

    @MainActor
    func testInvalidImportLeavesTheBoardUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-import-bad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = CardStore(cache: AssetCache(root: root), player: SpeechPlayer())
        let want = Card(word: "want", slug: "want", imageURL: "", audioURL: "")
        store.seedLocalBoard(cards: [want], folders: [])
        XCTAssertEqual(store.currentWordSlugs, ["want"])

        var object = try JSONSerialization.jsonObject(with: sampleData()) as! [String: Any]
        var boards = object["boards"] as! [[String: Any]]
        var cells = boards[0]["cells"] as! [[String: Any]]
        cells[0]["target"] = "does-not-exist"
        boards[0]["cells"] = cells
        object["boards"] = boards
        let bad = root.appendingPathComponent("bad.board.json")
        try JSONSerialization.data(withJSONObject: object).write(to: bad)

        XCTAssertThrowsError(try store.importBoard(from: bad))
        XCTAssertFalse(store.hasImportedBoard)
        XCTAssertEqual(store.currentWordSlugs, ["want"])
        XCTAssertEqual(store.settings.colorMode, ProfileSettings.default.colorMode)
    }
}
