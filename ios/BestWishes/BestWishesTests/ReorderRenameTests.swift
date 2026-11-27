import XCTest
@testable import BestWishes

@MainActor
final class ReorderRenameTests: XCTestCase {
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-reorder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return AssetCache(root: root)
    }

    private func makeStore(cache: AssetCache? = nil, profile: KidProfile = .child1) throws -> CardStore {
        let cache = try cache ?? makeCache()
        return CardStore(cache: cache, player: SpeechPlayer(), profile: profile)
    }

    private func seedTree(_ store: CardStore) {
        let juice = card("juice")
        let iceCream = card("ice cream", slug: "ice-cream")
        let want = card("want")
        let daddy = card("Daddy", slug: "daddy")
        let food = BoardFolder(id: "food", name: "Food", parentId: nil, memberSlugs: ["juice", "ice-cream"])
        store.seedLocalBoard(cards: [juice, iceCream, want, daddy], folders: [food])
    }

    private func payloadWord(_ word: String, slug: String? = nil, folderId: String? = nil) -> BoardPayloadItem {
        let slug = slug ?? word.lowercased()
        return BoardPayloadItem(
            kind: .word,
            slug: slug,
            word: word,
            imageURL: "/v1/cards/\(slug)/image",
            audioURL: "/v1/cards/\(slug)/audio",
            folderId: folderId
        )
    }

    private func payloadFolder(id: String, name: String, children: [String]) -> BoardPayloadItem {
        BoardPayloadItem(
            kind: .folder,
            slug: id,
            word: name,
            imageURL: "/system/folder.png",
            children: children,
            name: name
        )
    }

    func testReorderOnRootPersistsAcrossReopen() throws {
        let cache = try makeCache()
        let store = try makeStore(cache: cache)
        seedTree(store)

        let original = store.currentItemIDs
        XCTAssertGreaterThanOrEqual(original.count, 2)
        let reordered = Array(original.reversed())
        XCTAssertNotEqual(original, reordered)

        store.reorderCurrentItems(ids: reordered)
        XCTAssertEqual(store.currentItemIDs, reordered)

        let reopened = try makeStore(cache: cache)
        seedTree(reopened)
        XCTAssertEqual(reopened.currentItemIDs, reordered)
        XCTAssertNotEqual(reopened.currentItemIDs, original)
    }

    func testFolderOrderIsIndependentOfRoot() throws {
        let store = try makeStore()
        seedTree(store)

        let rootOriginal = store.currentItemIDs
        let rootReordered = Array(rootOriginal.reversed())
        store.reorderCurrentItems(ids: rootReordered)
        XCTAssertEqual(store.currentItemIDs, rootReordered)

        store.openFolder(id: "food")
        let folderOriginal = store.currentItemIDs
        XCTAssertEqual(Set(folderOriginal), Set(["juice", "ice-cream"]))
        XCTAssertGreaterThanOrEqual(folderOriginal.count, 2)
        let folderReordered = Array(folderOriginal.reversed())
        XCTAssertNotEqual(folderOriginal, folderReordered)
        store.reorderCurrentItems(ids: folderReordered)
        XCTAssertEqual(store.currentItemIDs, folderReordered)

        store.goHome()
        XCTAssertEqual(store.currentItemIDs, rootReordered)

        store.openFolder(id: "food")
        XCTAssertEqual(store.currentItemIDs, folderReordered)
    }

    func testMoveCurrentItemIsTheDropPath() throws {
        let store = try makeStore()
        seedTree(store)
        let ids = store.currentItemIDs
        XCTAssertGreaterThanOrEqual(ids.count, 2)
        let first = ids[0]
        let second = ids[1]

        store.moveCurrentItem(id: second, before: first)
        XCTAssertEqual(store.currentItemIDs.first, second)
        XCTAssertEqual(store.currentItemIDs[1], first)
    }

    func testChild1OrderAndLabelsDivergeFromChild2AfterSwitch() throws {
        let cache = try makeCache()
        let suiteName = "bw-reorder-profile-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profiles = ProfileStore(defaults: defaults)
        let store = CardStore(cache: cache, player: SpeechPlayer(), profile: profiles.active)
        let grid = GridLayout(defaults: defaults, profile: profiles.active)
        seedTree(store)

        let child1Order = Array(store.currentItemIDs.reversed())
        store.reorderCurrentItems(ids: child1Order)
        store.setDisplayLabel("sip", for: "juice")
        XCTAssertEqual(store.currentItemIDs, child1Order)
        XCTAssertEqual(store.displayLabel(for: card("juice")), "sip")

        profiles.switchTo(.child2, overlay: store, grid: grid)

        XCTAssertEqual(store.activeProfile, .child2)
        XCTAssertNotEqual(store.currentItemIDs, child1Order)
        XCTAssertEqual(store.displayLabel(for: card("juice")), "juice")

        var child2Order = store.currentItemIDs
        XCTAssertGreaterThanOrEqual(child2Order.count, 2)
        child2Order.append(child2Order.removeFirst())
        store.reorderCurrentItems(ids: child2Order)
        store.setDisplayLabel("drink", for: "juice")
        let child2Saved = store.currentItemIDs
        XCTAssertEqual(child2Saved, child2Order)
        XCTAssertNotEqual(child2Saved, child1Order)
        XCTAssertEqual(store.displayLabel(for: card("juice")), "drink")

        profiles.switchTo(.child1, overlay: store, grid: grid)

        XCTAssertEqual(store.activeProfile, .child1)
        XCTAssertEqual(store.currentItemIDs, child1Order)
        XCTAssertEqual(store.displayLabel(for: card("juice")), "sip")
        XCTAssertNotEqual(store.currentItemIDs, child2Saved)
        XCTAssertNotEqual(store.displayLabel(for: card("juice")), "drink")
    }

    func testApplyBoardKeepsSavedOrderAndAppendsNewId() throws {
        let store = try makeStore()
        seedTree(store)
        let saved = Array(store.currentItemIDs.reversed())
        store.reorderCurrentItems(ids: saved)
        XCTAssertEqual(store.currentItemIDs, saved)

        let extraWord = "hello"
        let extraSlug = "hello"
        store.applyBoard(
            BoardResponse(
                items: [
                    payloadFolder(id: "food", name: "Food", children: ["juice", "ice-cream"]),
                    payloadWord("Daddy", slug: "daddy"),
                    payloadWord("want"),
                    payloadWord(extraWord, slug: extraSlug),
                ],
                folderId: nil,
                count: 4
            )
        )

        XCTAssertEqual(Array(store.currentItemIDs.dropLast()), saved)
        XCTAssertEqual(store.currentItemIDs.last, extraSlug)
        XCTAssertTrue(store.currentItemIDs.contains(extraSlug))
        XCTAssertEqual(Set(saved).isSubset(of: Set(store.currentItemIDs)), true)
    }

    func testDisplayLabelOverlayShowsOnGridAndStripWhileSpeakUsesSlugMP3() throws {
        let cache = try makeCache()
        let player = SpeechPlayer()
        let store = CardStore(cache: cache, player: player)
        seedTree(store)

        let juice = try XCTUnwrap(store.cards.first { $0.slug == "juice" })
        XCTAssertEqual(store.displayLabel(for: juice), juice.word)
        XCTAssertEqual(juice.word, "juice")
        XCTAssertEqual(juice.slug, "juice")
        XCTAssertEqual(juice.audioURL, "/v1/cards/juice/audio")

        store.setDisplayLabel("sip", for: juice.slug)

        let stillJuice = try XCTUnwrap(store.cards.first { $0.slug == "juice" })
        XCTAssertEqual(store.displayLabel(for: stillJuice), "sip")
        XCTAssertEqual(stillJuice.word, "juice")
        XCTAssertEqual(stillJuice.slug, "juice")
        XCTAssertEqual(stillJuice.audioURL, "/v1/cards/juice/audio")

        store.openFolder(id: "food")
        let juiceItem = try XCTUnwrap(store.currentItems.first { $0.id == "juice" })
        XCTAssertEqual(store.displayLabel(for: juiceItem), "sip")

        let dir = cache.directory(for: "juice")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("BestWishes-test-mp3".utf8).write(to: cache.audioURL(for: "juice"))
        XCTAssertTrue(cache.hasAudio("juice"))

        store.tap(stillJuice)
        XCTAssertEqual(store.strip.slugs, ["juice"])
        XCTAssertEqual(store.displayLabel(for: store.strip.cards[0]), "sip")
        XCTAssertEqual(player.lastSpeakSequence, ["juice"])
        XCTAssertEqual(player.lastSpeakAudioURLs, [cache.audioURL(for: "juice")])
        XCTAssertEqual(player.lastSpeakAudioURLs.map(\.lastPathComponent), ["audio.mp3"])
        XCTAssertTrue(player.lastSpeakAudioURLs[0].path.contains("/juice/"))

        store.speakStrip()
        XCTAssertEqual(player.lastSpeakSequence, ["juice"])
        XCTAssertEqual(player.lastSpeakAudioURLs.first, cache.audioURL(for: "juice"))
        XCTAssertEqual(player.lastSpeakAudioURLs.first?.lastPathComponent, "audio.mp3")
    }

    func testFolderDisplayLabelUsesSameOverlay() throws {
        let store = try makeStore()
        seedTree(store)
        let food = try XCTUnwrap(store.grouping.folder(id: "food"))
        XCTAssertEqual(store.displayLabel(for: food), "Food")
        store.setDisplayLabel("Snacks", for: "food")
        XCTAssertEqual(store.displayLabel(for: food), "Snacks")
        store.openFolder(id: "food")
        XCTAssertEqual(store.currentFolderName, "Snacks")
        let stillFood = try XCTUnwrap(store.grouping.folder(id: "food"))
        XCTAssertEqual(stillFood.name, "Food")
    }

    func testKidModeAndKidLaunchArgHideEditChrome() {
        let suiteName = "bw-reorder-chrome-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let kid = CaregiverMode(defaults: defaults)
        XCTAssertFalse(kid.isCaregiver)
        XCTAssertFalse(kid.showsEditChrome)
        kid.enterEdit()
        XCTAssertFalse(kid.showsEditChrome)

        let launched = CaregiverMode(defaults: UserDefaults(suiteName: suiteName + "-b")!)
        launched.applyLaunchArguments(["-KidMode"])
        XCTAssertFalse(launched.showsEditChrome)
        XCTAssertFalse(launched.isEditing)
        XCTAssertFalse(launched.isCaregiver)
    }

    func testReorderAndRenameDoNotCallCardsPatchOrOrderAPI() throws {
        FixtureURLProtocol.reset()
        FixtureURLProtocol.recorded = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: config)
        let api = APIClient(baseURL: URL(string: "https://bestwishes.test")!, session: session)
        let store = CardStore(api: api, cache: try makeCache(), player: SpeechPlayer())
        seedTree(store)

        store.reorderCurrentItems(ids: Array(store.currentItemIDs.reversed()))
        store.setDisplayLabel("sip", for: "juice")
        store.moveCurrentItem(id: store.currentItemIDs[0], before: store.currentItemIDs[1])

        XCTAssertTrue(FixtureURLProtocol.requests.isEmpty)
        XCTAssertFalse(FixtureURLProtocol.requests.contains { $0.httpMethod == "PATCH" || $0.httpMethod == "PUT" })
        XCTAssertFalse(FixtureURLProtocol.requests.contains { $0.url?.path.contains("order") == true })
        session.invalidateAndCancel()
        FixtureURLProtocol.reset()
    }
}
