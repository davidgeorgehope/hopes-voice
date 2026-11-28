import XCTest
@testable import BestWishes

final class CoreWordsTests: XCTestCase {
    @MainActor
    private func makeStore(_ root: URL) -> CardStore {
        CardStore(api: APIClient(baseURL: APIClient.unreachableBaseURL), cache: AssetCache(root: root), player: SpeechPlayer())
    }

    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testFixedOrderOfThirtySixWords() {
        XCTAssertEqual(CoreWords.words.count, 36)
        XCTAssertEqual(Set(CoreWords.words.map { $0.lowercased() }).count, 36, "no duplicates")
        XCTAssertEqual(Array(CoreWords.words.prefix(6)), ["I", "you", "want", "more", "go", "stop"])
    }

    @MainActor
    func testCoreHomeUsesExistingButtonsThenFolders() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root)
        let want = Card(word: "want", slug: "want", imageURL: "", audioURL: "")
        let car = Card(word: "car", slug: "car", imageURL: "", audioURL: "")
        let toys = BoardFolder(id: "toys", name: "Toys", parentId: nil, memberSlugs: ["car"])
        store.seedLocalBoard(cards: [want, car], folders: [toys])

        XCTAssertEqual(store.homeLayout, .myBoard, "default home is the family's board")
        store.setHomeLayout(.coreWords)
        let ids = store.currentItems.map(\.id)
        XCTAssertEqual(ids.count, 37)
        XCTAssertEqual(ids[2], "want", "want uses the existing button")
        XCTAssertEqual(ids[1], "core:you", "you has no button yet, so it's a word tile")
        XCTAssertEqual(ids.last, "folder:toys", "folders come after the core words")
        XCTAssertFalse(ids.contains("car"), "loose words stay in their folders")

        // Chosen per profile and remembered.
        XCTAssertEqual(makeStore(root).homeLayout, .coreWords)
        XCTAssertEqual(store.slots(rows: 6, columns: 6, editing: false).prefix(3).compactMap { slot -> String? in
            if case .item(let item, _) = slot { return item.id } else { return nil }
        }, ["core:i", "core:you", "want"], "fixed spots in reading order")
        store.setHomeLayout(.myBoard)
        XCTAssertEqual(Set(store.currentItems.map(\.id)), ["folder:toys", "want"], "back to the family's board")
    }

    @MainActor
    func testCoreWordsFolderBacksTheLayoutAndIsNeverShownAsAFolder() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root)
        let you = Card(word: "you", slug: "you", imageURL: "/assets/you/image.png", audioURL: "")
        let car = Card(word: "car", slug: "car", imageURL: "", audioURL: "")
        let store_ = BoardFolder(id: CoreWords.storeFolderId, name: "Core words", parentId: nil, memberSlugs: ["you"])
        store.seedLocalBoard(cards: [you, car], folders: [store_])

        XCTAssertEqual(store.currentItems.map(\.id), ["car"], "My board doesn't show the core-words folder")
        store.setHomeLayout(.coreWords)
        let ids = store.currentItems.map(\.id)
        XCTAssertEqual(ids[1], "you", "the core tile is the folder's real button, with its picture")
        XCTAssertEqual(ids.count, 36, "no folder tile for the core words")
    }

    @MainActor
    func testTappingAWordTileAddsItToTheBar() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root)
        store.messageBar.speakOnTap = false
        store.seedLocalBoard(cards: [], folders: [])
        store.setHomeLayout(.coreWords)
        guard case .word(let you) = store.currentItems[1] else { return XCTFail("no tile") }
        store.select(.word(you))
        XCTAssertEqual(store.strip.chips.map { store.chipLabel($0) }, ["you"])
    }
}
