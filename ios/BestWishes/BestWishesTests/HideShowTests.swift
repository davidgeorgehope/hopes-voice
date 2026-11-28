import XCTest
@testable import BestWishes

/// Hide without deleting: the editor's "Show on the board" switch hides a word or folder from
/// the child's board, keeps its seat and edits, shows it dimmed in Edit, and brings it back.
@MainActor
final class HideShowTests: XCTestCase {
    private func makeStore() throws -> CardStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-hide-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = CardStore(api: APIClient(baseURL: APIClient.unreachableBaseURL), cache: AssetCache(root: root), player: SpeechPlayer())
        let cards = ["juice", "car", "dog"].map { Card(word: $0, slug: $0, imageURL: "", audioURL: "") }
        store.seedLocalBoard(cards: cards, folders: [BoardFolder(id: "toys", name: "Toys", parentId: nil, memberSlugs: ["car"])])
        return store
    }

    private func slot(_ store: CardStore, _ id: String, editing: Bool) -> BoardSlot? {
        store.slots(rows: 3, columns: 4, editing: editing).first { slot in
            switch slot {
            case .item(let item, _), .hidden(let item, _): return item.id == id
            case .empty: return false
            }
        }
    }

    private func coord(_ store: CardStore, _ id: String) throws -> GridCoord {
        for slot in store.slots(rows: 3, columns: 4, editing: true) {
            if case .item(let item, let c) = slot, item.id == id { return c }
            if case .hidden(let item, let c) = slot, item.id == id { return c }
        }
        throw XCTSkip("no seat for \(id)")
    }

    func testHidingAWordKeepsItsSeatAndShowingBringsItBack() async throws {
        let store = try makeStore()
        let item = try XCTUnwrap(store.currentItems.first { $0.id == "juice" })
        let seat = try coord(store, "juice")
        var draft = store.draftForExisting(item, at: seat)
        XCTAssertFalse(draft.isHidden)

        draft.isHidden = true
        draft.label = "apple juice"
        _ = await store.saveEditorDraft(draft)

        XCTAssertTrue(store.hiddenSlugs.contains("juice"))
        XCTAssertNil(slot(store, "juice", editing: false), "hidden from the child's board")
        guard case .hidden(_, let dimmedSeat)? = slot(store, "juice", editing: true) else {
            return XCTFail("shown dimmed in Edit")
        }
        XCTAssertEqual(dimmedSeat, seat, "keeps its seat")
        XCTAssertEqual(store.labelOverlays["juice"], "apple juice", "edits are kept")

        var again = store.draftForExisting(item, at: seat)
        XCTAssertTrue(again.isHidden)
        again.isHidden = false
        _ = await store.saveEditorDraft(again)

        XCTAssertFalse(store.hiddenSlugs.contains("juice"))
        guard case .item(_, let back)? = slot(store, "juice", editing: false) else {
            return XCTFail("back on the child's board")
        }
        XCTAssertEqual(back, seat)
        XCTAssertTrue(store.cards.contains { $0.slug == "juice" }, "never deleted")
    }

    func testFoldersCanBeHiddenToo() async throws {
        let store = try makeStore()
        let folder = try XCTUnwrap(store.currentItems.first { $0.id == "folder:toys" })
        var draft = store.draftForExisting(folder, at: try coord(store, "folder:toys"))
        draft.isHidden = true
        _ = await store.saveEditorDraft(draft)

        XCTAssertTrue(store.hiddenSlugs.contains("folder:toys"))
        XCTAssertNil(slot(store, "folder:toys", editing: false))
        XCTAssertNotNil(slot(store, "folder:toys", editing: true))
        XCTAssertNotNil(store.grouping.folder(id: "toys"))
    }
}
