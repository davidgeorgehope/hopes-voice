import XCTest
@testable import BestWishes

@MainActor
final class EditBoardTests: XCTestCase {
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
        let cache = AssetCache(root: root)
        return CardStore(cache: cache, player: SpeechPlayer())
    }

    private func seedTree(_ store: CardStore, extra: [Card] = []) {
        let juice = card("juice")
        let iceCream = card("ice cream", slug: "ice-cream")
        let want = card("want")
        let food = BoardFolder(id: "food", name: "Food", parentId: nil, memberSlugs: ["juice", "ice-cream"])
        store.seedLocalBoard(cards: [juice, iceCream, want] + extra, folders: [food])
    }

    func testHideAfterConfirmRemovesSlugFromCurrentBoard() throws {
        let store = try makeStore()
        seedTree(store)
        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        XCTAssertFalse(store.hiddenSlugs.contains("want"))

        store.hideAfterConfirm("want")

        XCTAssertFalse(store.currentWordSlugs.contains("want"))
        XCTAssertFalse(store.currentItems.contains { item in
            if case .word(let card) = item { return card.slug == "want" }
            return false
        })
        XCTAssertTrue(store.hiddenSlugs.contains("want"))
    }

    func testKidVisibleItemsOmitHiddenSlugs() throws {
        let store = try makeStore()
        seedTree(store)
        XCTAssertEqual(store.currentWordSlugs, ["want"])

        store.hideAfterConfirm("want")

        XCTAssertEqual(store.currentWordSlugs, [])
        XCTAssertFalse(store.currentItems.contains { !$0.isFolder })
        XCTAssertEqual(store.currentFolderIds, ["food"])
    }

    func testUnhideRestoresCardAndHiddenListIncludesIt() throws {
        let store = try makeStore()
        seedTree(store)
        store.hideAfterConfirm("want")
        XCTAssertEqual(store.hiddenListSlugs, ["want"])
        XCTAssertEqual(store.hiddenCards.map(\.word), ["want"])
        XCTAssertFalse(store.currentWordSlugs.contains("want"))

        store.unhide("want")

        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        XCTAssertTrue(store.hiddenCards.isEmpty)
        XCTAssertFalse(store.hiddenSlugs.contains("want"))
    }

    func testProbeSlugsAreStrippedViaSameHidePathWhenSeeded() throws {
        let store = try makeStore()
        let probe = card("hello-test-probe")
        let bubble = card("bubble")
        seedTree(store, extra: [probe, bubble])
        XCTAssertTrue(store.currentWordSlugs.contains("hello-test-probe"))
        XCTAssertTrue(store.currentWordSlugs.contains("bubble"))
        XCTAssertTrue(store.currentWordSlugs.contains("want"))

        store.applyProbeHides()

        XCTAssertFalse(store.currentWordSlugs.contains("hello-test-probe"))
        XCTAssertFalse(store.currentWordSlugs.contains("bubble"))
        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        XCTAssertTrue(store.hiddenListSlugs.contains("hello-test-probe"))
        XCTAssertTrue(store.hiddenListSlugs.contains("bubble"))
        XCTAssertTrue(store.hiddenSlugs.contains("hello-test-probe"))
        XCTAssertTrue(store.hiddenSlugs.contains("bubble"))
    }

    func testHideSurvivesReopenFromSameCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-edit-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = AssetCache(root: root)

        let first = CardStore(cache: cache, player: SpeechPlayer())
        seedTree(first)
        XCTAssertTrue(first.currentWordSlugs.contains("want"))
        first.hideAfterConfirm("want")
        XCTAssertFalse(first.currentWordSlugs.contains("want"))

        let reopened = CardStore(cache: cache, player: SpeechPlayer())
        XCTAssertTrue(reopened.hiddenSlugs.contains("want"))
        seedTree(reopened)
        XCTAssertFalse(reopened.currentWordSlugs.contains("want"))
        XCTAssertEqual(reopened.hiddenListSlugs, ["want"])
    }

    func testSpeakStripStillRecordsSequenceAfterHidingADifferentCard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-edit-speak-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = AssetCache(root: root)
        let player = SpeechPlayer()
        let store = CardStore(cache: cache, player: player)
        seedTree(store)

        let i = card("I", slug: "i")
        store.integrateNewCard(i)
        try FileManager.default.createDirectory(at: cache.directory(for: "i"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache.directory(for: "want"), withIntermediateDirectories: true)
        try Data("BestWishes-test-mp3".utf8).write(to: cache.audioURL(for: "i"))
        try Data("BestWishes-test-mp3".utf8).write(to: cache.audioURL(for: "want"))

        store.appendSlugsFromBoard(["i", "want"])
        XCTAssertEqual(store.strip.slugs, ["i", "want"])

        store.hideAfterConfirm("juice")
        XCTAssertFalse(store.currentWordSlugs.contains("juice"))

        store.speakStrip()
        XCTAssertEqual(player.lastSpeakSequence, ["i", "want"])
        XCTAssertEqual(store.strip.slugs, ["i", "want"])
    }

    func testFolderOpenBackHomeStillWorkAfterHide() throws {
        let store = try makeStore()
        seedTree(store)
        store.hideAfterConfirm("want")
        XCTAssertTrue(store.isAtRoot)
        XCTAssertEqual(store.currentFolderIds, ["food"])
        XCTAssertFalse(store.currentWordSlugs.contains("want"))

        store.openFolder(id: "food")
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertEqual(Set(store.currentWordSlugs), Set(["juice", "ice-cream"]))

        store.goBack()
        XCTAssertTrue(store.isAtRoot)
        XCTAssertNil(store.currentFolderName)
        XCTAssertEqual(store.currentFolderIds, ["food"])

        store.openFolder(id: "food")
        store.goHome()
        XCTAssertTrue(store.isAtRoot)
        XCTAssertEqual(store.currentFolderIds, ["food"])
        XCTAssertFalse(store.currentWordSlugs.contains("want"))
    }

    func testHideInsideFolderRemovesOnlyThatBoardMember() throws {
        let store = try makeStore()
        seedTree(store)
        store.openFolder(id: "food")
        XCTAssertTrue(store.currentWordSlugs.contains("juice"))

        store.hideAfterConfirm("juice")

        XCTAssertFalse(store.currentWordSlugs.contains("juice"))
        XCTAssertTrue(store.currentWordSlugs.contains("ice-cream"))
        XCTAssertTrue(store.hiddenListSlugs.contains("juice"))

        store.goHome()
        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        XCTAssertFalse(store.currentWordSlugs.contains("juice"))
    }
}

@MainActor
final class CaregiverEditModeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "bw-edit-mode-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testKidModeHidesEditChromeAndHiddenList() {
        let mode = CaregiverMode(defaults: defaults)
        XCTAssertFalse(mode.isCaregiver)
        XCTAssertFalse(mode.showsEditButton)
        XCTAssertFalse(mode.showsEditChrome)
        XCTAssertFalse(mode.showsHiddenList)
        mode.enterEdit()
        XCTAssertFalse(mode.isEditing)
        XCTAssertFalse(mode.showsEditChrome)
    }

    func testEnterEditThenLockLeavesEdit() {
        let mode = CaregiverMode(defaults: defaults)
        mode.unlock()
        XCTAssertTrue(mode.showsEditButton)
        XCTAssertFalse(mode.showsEditChrome)

        mode.enterEdit()
        XCTAssertTrue(mode.isEditing)
        XCTAssertTrue(mode.showsEditChrome)
        XCTAssertTrue(mode.showsHiddenList)

        mode.exitEdit()
        XCTAssertFalse(mode.showsEditChrome)

        mode.enterEdit()
        mode.lock()
        XCTAssertFalse(mode.isCaregiver)
        XCTAssertFalse(mode.isEditing)
        XCTAssertFalse(mode.showsEditButton)
        XCTAssertFalse(mode.showsEditChrome)
        XCTAssertFalse(mode.showsHiddenList)
    }

    func testLaunchArgEditModeUnlocksAndEntersEdit() {
        let mode = CaregiverMode(defaults: defaults)
        mode.applyLaunchArguments(["-EditMode"])
        XCTAssertTrue(mode.isCaregiver)
        XCTAssertTrue(mode.isEditing)
        XCTAssertTrue(mode.showsEditChrome)

        mode.applyLaunchArguments(["-KidMode"])
        XCTAssertFalse(mode.showsEditChrome)
        XCTAssertFalse(mode.isEditing)
    }
}
