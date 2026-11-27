import XCTest
@testable import BestWishes

@MainActor
final class BoardSearchTests: XCTestCase {
    private func card(_ word: String, slug: String? = nil) -> Card {
        let slug = slug ?? word.lowercased()
        return Card(
            word: word,
            slug: slug,
            imageURL: "/v1/cards/\(slug)/image",
            audioURL: "/v1/cards/\(slug)/audio"
        )
    }

    private func makeCache() throws -> AssetCache {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return AssetCache(root: root)
    }

    private func makeStore(cache: AssetCache? = nil) throws -> CardStore {
        let cache = try cache ?? makeCache()
        return CardStore(cache: cache, player: SpeechPlayer(), profile: .child1)
    }

    private func seedTree(_ store: CardStore) {
        let cores = CoreVocabulary.ordered.map { card($0.word, slug: $0.slug) }
        let juice = card("juice")
        let iceCream = card("ice cream", slug: "ice-cream")
        let daddy = card("Daddy", slug: "daddy")
        let food = BoardFolder(id: "food", name: "Food", parentId: nil, memberSlugs: ["juice", "ice-cream"])
        store.seedLocalBoard(cards: cores + [juice, iceCream, daddy], folders: [food])
    }

    private func wordSlugs(in items: [BoardItem]) -> [String] {
        items.compactMap {
            if case .word(let card) = $0 { return card.slug }
            return nil
        }
    }

    private func folderIds(in items: [BoardItem]) -> [String] {
        items.compactMap {
            if case .folder(let folder) = $0 { return folder.id }
            return nil
        }
    }

    func testCaseInsensitiveSubstringOnDisplayLabelWordAndSlug() throws {
        let store = try makeStore()
        seedTree(store)
        store.setDisplayLabel("sippy", for: "juice")
        store.openFolder(id: "food")
        XCTAssertEqual(Set(store.currentWordSlugs), Set(["juice", "ice-cream"]))

        store.setSearchQuery("SIPPY")
        XCTAssertEqual(wordSlugs(in: store.filteredCurrentItems), ["juice"])
        XCTAssertEqual(store.displayLabel(for: try XCTUnwrap(store.cards.first { $0.slug == "juice" })), "sippy")

        store.setSearchQuery("Juice")
        XCTAssertEqual(wordSlugs(in: store.filteredCurrentItems), ["juice"])

        store.setSearchQuery("ICE-CREAM")
        XCTAssertEqual(wordSlugs(in: store.filteredCurrentItems), ["ice-cream"])

        store.setSearchQuery("cream")
        XCTAssertEqual(wordSlugs(in: store.filteredCurrentItems), ["ice-cream"])
    }

    func testMatchingFolderStaysAndNonMatchingWordHides() throws {
        let store = try makeStore()
        seedTree(store)
        XCTAssertTrue(store.isAtRoot)
        XCTAssertTrue(store.currentFolderIds.contains("food"))
        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        XCTAssertTrue(store.currentWordSlugs.contains("daddy"))

        store.setSearchQuery("FOOD")
        XCTAssertEqual(folderIds(in: store.filteredCurrentItems), ["food"])
        XCTAssertFalse(wordSlugs(in: store.filteredCurrentItems).contains("want"))
        XCTAssertFalse(wordSlugs(in: store.filteredCurrentItems).contains("daddy"))
        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        XCTAssertTrue(store.currentFolderIds.contains("food"))
    }

    func testFolderDisplayNameAndIdMatch() throws {
        let store = try makeStore()
        seedTree(store)
        store.setDisplayLabel("Snacks", for: "food")

        store.setSearchQuery("snack")
        XCTAssertEqual(folderIds(in: store.filteredCurrentItems), ["food"])

        store.setSearchQuery("Food")
        XCTAssertEqual(folderIds(in: store.filteredCurrentItems), ["food"])

        store.setSearchQuery("food")
        XCTAssertEqual(folderIds(in: store.filteredCurrentItems), ["food"])
    }

    func testFoodChildDoesNotSurfaceOnRootBoard() throws {
        let store = try makeStore()
        seedTree(store)
        XCTAssertTrue(store.isAtRoot)
        XCTAssertFalse(store.currentWordSlugs.contains("juice"))
        XCTAssertFalse(store.currentWordSlugs.contains("ice-cream"))

        store.setSearchQuery("juice")
        XCTAssertFalse(wordSlugs(in: store.filteredCurrentItems).contains("juice"))
        XCTAssertTrue(store.filteredCurrentItems.isEmpty)

        store.setSearchQuery("ice-cream")
        XCTAssertFalse(wordSlugs(in: store.filteredCurrentItems).contains("ice-cream"))
        XCTAssertTrue(store.filteredCurrentItems.isEmpty)

        store.openFolder(id: "food")
        store.setSearchQuery("juice")
        XCTAssertEqual(wordSlugs(in: store.filteredCurrentItems), ["juice"])
        XCTAssertFalse(wordSlugs(in: store.filteredCurrentItems).contains("want"))
    }

    func testEmptyAndClearedQueryEqualsUnfilteredCurrentBoard() throws {
        let store = try makeStore()
        seedTree(store)
        let unfiltered = store.currentItems.map(\.id)
        XCTAssertFalse(unfiltered.isEmpty)
        XCTAssertEqual(store.filteredCurrentItems.map(\.id), unfiltered)

        store.setSearchQuery("food")
        XCTAssertNotEqual(store.filteredCurrentItems.map(\.id), unfiltered)
        XCTAssertEqual(store.currentItems.map(\.id), unfiltered)

        store.setSearchQuery("")
        XCTAssertEqual(store.filteredCurrentItems.map(\.id), unfiltered)

        store.setSearchQuery("FOOD")
        store.setSearchQuery("   ")
        XCTAssertEqual(store.filteredCurrentItems.map(\.id), unfiltered)
    }

    func testKidChromeHidesSearchAndCaregiverChromeShowsIt() {
        let suiteName = "bw-search-chrome-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mode = CaregiverMode(defaults: defaults)
        XCTAssertFalse(mode.isCaregiver)
        XCTAssertFalse(mode.showsSearchChrome)
        XCTAssertFalse(mode.showsAddChrome)

        mode.unlock()
        XCTAssertTrue(mode.showsSearchChrome)
        XCTAssertTrue(mode.showsAddChrome)

        mode.lock()
        XCTAssertFalse(mode.showsSearchChrome)
        XCTAssertFalse(mode.showsAddChrome)

        mode.applyLaunchArguments(["-CaregiverMode"])
        XCTAssertTrue(mode.showsSearchChrome)

        mode.applyLaunchArguments(["-KidMode"])
        XCTAssertFalse(mode.showsSearchChrome)
    }

    func testQueryDoesNotChangeHideOrOrderMembership() throws {
        let store = try makeStore()
        seedTree(store)
        store.hideAfterConfirm("daddy")
        XCTAssertFalse(store.currentWordSlugs.contains("daddy"))

        let reordered = Array(store.currentItemIDs.reversed())
        store.reorderCurrentItems(ids: reordered)
        XCTAssertEqual(store.currentItemIDs, reordered)

        let hidden = store.hiddenSlugs
        let order = store.orderOverlays
        let currentIDs = store.currentItemIDs
        let currentWords = store.currentWordSlugs
        let currentFolders = store.currentFolderIds

        store.setSearchQuery("food")
        XCTAssertEqual(store.hiddenSlugs, hidden)
        XCTAssertEqual(store.orderOverlays, order)
        XCTAssertEqual(store.currentItemIDs, currentIDs)
        XCTAssertEqual(store.currentWordSlugs, currentWords)
        XCTAssertEqual(store.currentFolderIds, currentFolders)
        XCTAssertFalse(store.currentWordSlugs.contains("daddy"))
        XCTAssertFalse(wordSlugs(in: store.filteredCurrentItems).contains("daddy"))
        XCTAssertEqual(folderIds(in: store.filteredCurrentItems), ["food"])

        store.setSearchQuery("")
        XCTAssertEqual(store.currentItemIDs, currentIDs)
        XCTAssertEqual(store.hiddenSlugs, hidden)
        XCTAssertEqual(store.orderOverlays, order)
    }

    func testReorderWhileFilteredKeepsFullBoardMembership() throws {
        let store = try makeStore()
        seedTree(store)
        let full = store.currentItemIDs
        XCTAssertGreaterThan(full.count, 1)

        store.setSearchQuery("food")
        let filteredIDs = store.filteredCurrentItems.map(\.id)
        XCTAssertFalse(filteredIDs.isEmpty)
        XCTAssertLessThan(filteredIDs.count, full.count)

        store.moveCurrentItem(id: full[1], before: full[0])
        XCTAssertEqual(Set(store.currentItemIDs), Set(full))
        XCTAssertEqual(store.currentItemIDs.count, full.count)
        XCTAssertEqual(store.currentItemIDs.first, full[1])
    }

    func testCoresRecentsAndStripAreNotFiltered() throws {
        let store = try makeStore()
        seedTree(store)
        let want = try XCTUnwrap(store.cards.first { $0.slug == "want" })
        let juice = try XCTUnwrap(store.cards.first { $0.slug == "juice" })
        store.tap(want)
        store.tap(juice)
        XCTAssertEqual(store.strip.slugs, ["want", "juice"])
        XCTAssertEqual(store.recentSlugs, ["juice", "want"])
        let cores = store.coreSlugs
        XCTAssertEqual(cores, CoreVocabulary.ordered.map(\.slug))

        store.setSearchQuery("zzzz-no-match")
        XCTAssertTrue(store.filteredCurrentItems.isEmpty)
        XCTAssertEqual(store.strip.slugs, ["want", "juice"])
        XCTAssertEqual(store.recentSlugs, ["juice", "want"])
        XCTAssertEqual(store.coreSlugs, cores)
        XCTAssertEqual(store.coreCards.map(\.slug), cores)
        XCTAssertEqual(store.recentCards.map(\.slug), ["juice", "want"])
    }

    func testFilteredMatchesPreserveUnfilteredRelativeOrder() throws {
        let store = try makeStore()
        seedTree(store)
        store.setSearchQuery("a")
        let filtered = store.filteredCurrentItems.map(\.id)
        let expected = store.currentItems.map(\.id).filter { filtered.contains($0) }
        XCTAssertEqual(filtered, expected)
        XCTAssertFalse(filtered.isEmpty)
    }

    func testSearchFieldIsDedicatedAndGatedInSource() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BestWishes/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"boardSearchField\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"addWordField\")"))
        XCTAssertTrue(source.contains("mode.showsSearchChrome"))
        XCTAssertTrue(source.contains("store.filteredCurrentItems"))
        XCTAssertTrue(source.contains("store.setSearchQuery"))
        XCTAssertFalse(source.contains("TextField(\"search this board\", text: $draft)"))
        XCTAssertTrue(source.contains("\"-SearchQuery\""))
    }
}
