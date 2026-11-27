import XCTest
@testable import BestWishes

@MainActor
final class FolderNavigationTests: XCTestCase {
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-folders-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = AssetCache(root: root)
        let player = SpeechPlayer()
        return CardStore(cache: cache, player: player)
    }

    private func seedTree(_ store: CardStore) {
        let juice = card("juice")
        let iceCream = card("ice cream", slug: "ice-cream")
        let want = card("want")
        let food = BoardFolder(id: "food", name: "Food", parentId: nil, memberSlugs: ["juice", "ice-cream"])
        store.seedLocalBoard(cards: [juice, iceCream, want], folders: [food])
    }

    func testOpenFolderShowsOnlyMembersThenBackAndHome() throws {
        let store = try makeStore()
        seedTree(store)

        XCTAssertTrue(store.isAtRoot)
        XCTAssertNil(store.currentFolderName)
        XCTAssertEqual(store.currentFolderIds, ["food"])
        XCTAssertEqual(store.currentWordSlugs, ["want"])
        XCTAssertFalse(store.currentWordSlugs.contains("juice"))
        XCTAssertFalse(store.currentWordSlugs.contains("ice-cream"))

        guard case .folder(let folder) = store.currentItems.first(where: \.isFolder) else {
            XCTFail("root board must include a folder cell")
            return
        }
        XCTAssertEqual(folder.id, "food")
        XCTAssertEqual(folder.name, "Food")

        store.openFolder(folder)

        XCTAssertFalse(store.isAtRoot)
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertEqual(Set(store.currentWordSlugs), Set(["juice", "ice-cream"]))
        XCTAssertFalse(store.currentWordSlugs.contains("want"))
        XCTAssertTrue(store.currentFolderIds.isEmpty)

        store.goBack()
        XCTAssertTrue(store.isAtRoot)
        XCTAssertNil(store.currentFolderName)
        XCTAssertEqual(store.currentFolderIds, ["food"])
        XCTAssertEqual(store.currentWordSlugs, ["want"])

        store.openFolder(id: "food")
        XCTAssertEqual(store.currentFolderName, "Food")
        store.goHome()
        XCTAssertTrue(store.isAtRoot)
        XCTAssertNil(store.currentFolderName)
        XCTAssertEqual(store.currentFolderIds, ["food"])
        XCTAssertEqual(store.currentWordSlugs, ["want"])
    }

    func testTapWordAppendsTapFolderDoesNot() throws {
        let store = try makeStore()
        seedTree(store)
        XCTAssertTrue(store.strip.isEmpty)

        guard case .folder(let folder) = store.currentItems.first(where: \.isFolder) else {
            XCTFail("root board must include a folder cell")
            return
        }
        let stripBeforeFolder = store.strip.slugs
        store.select(.folder(folder))
        XCTAssertEqual(store.strip.slugs, stripBeforeFolder)
        XCTAssertEqual(store.currentFolderName, "Food")

        guard case .word(let juice) = store.currentItems.first(where: {
            if case .word(let card) = $0 { return card.slug == "juice" }
            return false
        }) else {
            XCTFail("Food folder must show juice")
            return
        }
        store.select(.word(juice))
        XCTAssertEqual(store.strip.slugs, ["juice"])
        XCTAssertEqual(store.currentFolderName, "Food")
    }

    func testFolderBackDoesNotBackspaceStripAndStripBackDoesNotLeaveFolder() throws {
        let store = try makeStore()
        seedTree(store)

        guard case .word(let want) = store.currentItems.first(where: {
            if case .word(let card) = $0 { return card.slug == "want" }
            return false
        }) else {
            XCTFail("root must show want")
            return
        }
        store.select(.word(want))
        XCTAssertEqual(store.strip.slugs, ["want"])

        store.openFolder(id: "food")
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertEqual(store.strip.slugs, ["want"])

        store.goBack()
        XCTAssertTrue(store.isAtRoot)
        XCTAssertEqual(store.strip.slugs, ["want"])

        store.openFolder(id: "food")
        store.backspaceStrip()
        XCTAssertTrue(store.strip.isEmpty)
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertFalse(store.isAtRoot)
    }

    func testIntegrateNewCardLandsOnCurrentFolder() throws {
        let store = try makeStore()
        seedTree(store)
        store.openFolder(id: "food")
        XCTAssertEqual(store.currentFolderName, "Food")

        let apple = card("apple")
        store.integrateNewCard(apple)

        XCTAssertTrue(store.currentWordSlugs.contains("apple"))
        XCTAssertTrue(store.currentWordSlugs.contains("juice"))
        XCTAssertFalse(store.currentWordSlugs.contains("want"))

        store.goHome()
        XCTAssertFalse(store.currentWordSlugs.contains("apple"))
        XCTAssertEqual(store.currentWordSlugs, ["want"])
        XCTAssertEqual(store.currentFolderIds, ["food"])
    }

    func testGroupingSurvivesReloadFromCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-folders-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = AssetCache(root: root)

        let first = CardStore(cache: cache, player: SpeechPlayer())
        seedTree(first)
        XCTAssertEqual(first.currentFolderIds, ["food"])

        let reopened = CardStore(cache: cache, player: SpeechPlayer())
        XCTAssertEqual(reopened.grouping.folder(id: "food")?.name, "Food")
        XCTAssertEqual(reopened.grouping.folder(id: "food")?.memberSlugs, ["juice", "ice-cream"])
    }
}
