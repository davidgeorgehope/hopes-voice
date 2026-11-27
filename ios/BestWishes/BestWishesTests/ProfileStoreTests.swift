import XCTest
@testable import BestWishes

@MainActor
final class ProfileStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var cacheRoot: URL!
    private var cache: AssetCache!
    private var player: SpeechPlayer!
    private var store: CardStore!
    private var grid: GridLayout!
    private var profiles: ProfileStore!

    override func setUp() {
        super.setUp()
        suiteName = "bw-profile-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent("bw-profile-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        cache = AssetCache(root: cacheRoot)
        player = SpeechPlayer()
        profiles = ProfileStore(defaults: defaults)
        store = CardStore(cache: cache, player: player, profile: profiles.active)
        grid = GridLayout(defaults: defaults, profile: profiles.active)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        if let cacheRoot {
            try? FileManager.default.removeItem(at: cacheRoot)
        }
        cacheRoot = nil
        super.tearDown()
    }

    private func card(_ word: String, slug: String? = nil) -> Card {
        let slug = slug ?? word.lowercased()
        return Card(
            word: word,
            slug: slug,
            imageURL: "/v1/cards/\(slug)/image",
            audioURL: "/v1/cards/\(slug)/audio"
        )
    }

    private func seedBoard() throws {
        let cores = CoreVocabulary.ordered.map { card($0.word, slug: $0.slug) }
        let juice = card("juice")
        let iceCream = card("ice cream", slug: "ice-cream")
        let food = BoardFolder(id: "food", name: "Food", parentId: nil, memberSlugs: ["juice", "ice-cream"])
        store.seedLocalBoard(cards: cores + [juice, iceCream], folders: [food])
        for item in cores + [juice, iceCream] {
            try seedAudio(slug: item.slug)
        }
    }

    private func seedAudio(slug: String) throws {
        let dir = cache.directory(for: slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("BestWishes-test-mp3".utf8).write(to: cache.audioURL(for: slug))
        XCTAssertTrue(cache.hasAudio(slug))
    }

    func testDefaultNamesAreChild1AndChild2AndMissingKeyIsChild1() {
        XCTAssertEqual(KidProfile.child1.rawValue, "Child 1")
        XCTAssertEqual(KidProfile.child2.rawValue, "Child 2")
        XCTAssertEqual(KidProfile.allCases.map(\.rawValue), ["Child 1", "Child 2"])
        XCTAssertNil(defaults.object(forKey: ProfileStore.defaultsKey))
        XCTAssertEqual(profiles.activeName, "Child 1")
        XCTAssertEqual(profiles.active, .child1)
        XCTAssertEqual(store.activeProfile, .child1)
    }

    func testHideSetsDivergeAfterSwitcherAndNameRoundTrips() throws {
        try seedBoard()
        XCTAssertEqual(profiles.activeName, "Child 1")
        XCTAssertTrue(store.currentWordSlugs.contains("juice") || store.grouping.folder(id: "food") != nil)

        store.hideAfterConfirm("juice")
        XCTAssertTrue(store.hiddenSlugs.contains("juice"))
        XCTAssertFalse(store.hiddenSlugs.contains("ice-cream"))

        store.openFolder(id: "food")
        XCTAssertEqual(store.currentFolderName, "Food")
        grid.setColumnCount(4)
        XCTAssertEqual(grid.columnCount, 4)

        store.appendSlugsFromBoard(["i", "want"])
        XCTAssertEqual(store.strip.slugs, ["i", "want"])

        profiles.switchTo(.child2, overlay: store, grid: grid)

        XCTAssertEqual(profiles.activeName, "Child 2")
        XCTAssertEqual(store.activeProfile, .child2)
        XCTAssertEqual(defaults.string(forKey: ProfileStore.defaultsKey), "Child 2")
        XCTAssertFalse(store.hiddenSlugs.contains("juice"))
        XCTAssertTrue(store.strip.isEmpty)
        XCTAssertTrue(store.isAtRoot)
        XCTAssertEqual(grid.columnCount, 3)

        store.hideAfterConfirm("ice-cream")
        XCTAssertTrue(store.hiddenSlugs.contains("ice-cream"))
        XCTAssertFalse(store.hiddenSlugs.contains("juice"))
        grid.setColumnCount(2)
        XCTAssertEqual(grid.columnCount, 2)

        let child1Hides = cache.loadHiddenSlugs(for: .child1)
        let child2Hides = cache.loadHiddenSlugs(for: .child2)
        XCTAssertNotEqual(child1Hides, child2Hides)
        XCTAssertEqual(child1Hides, ["juice"])
        XCTAssertEqual(child2Hides, ["ice-cream"])

        profiles.switchTo(.child1, overlay: store, grid: grid)

        XCTAssertEqual(profiles.activeName, "Child 1")
        XCTAssertEqual(store.activeProfile, .child1)
        XCTAssertEqual(store.hiddenSlugs, ["juice"])
        XCTAssertFalse(store.hiddenSlugs.contains("ice-cream"))
        XCTAssertNotEqual(store.hiddenSlugs, cache.loadHiddenSlugs(for: .child2))
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertEqual(grid.columnCount, 4)
        XCTAssertTrue(store.strip.isEmpty)

        let reopened = ProfileStore(defaults: defaults)
        XCTAssertEqual(reopened.activeName, "Child 1")
        XCTAssertEqual(defaults.string(forKey: ProfileStore.defaultsKey), "Child 1")

        profiles.switchTo(.child2, overlay: store, grid: grid)
        let reopenedChild2 = ProfileStore(defaults: defaults)
        XCTAssertEqual(reopenedChild2.activeName, "Child 2")
        XCTAssertEqual(defaults.string(forKey: ProfileStore.defaultsKey), "Child 2")

        let reopenedStore = CardStore(cache: cache, player: SpeechPlayer(), profile: reopenedChild2.active)
        XCTAssertEqual(reopenedStore.hiddenSlugs, ["ice-cream"])
        XCTAssertFalse(reopenedStore.hiddenSlugs.contains("juice"))
    }

    func testSwitchKeepsSharedBoardCoresAndSpeakCachedMP3() throws {
        try seedBoard()
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        let boardSlugs = store.cards.map(\.slug)

        store.hideAfterConfirm("juice")
        store.appendSlugsFromBoard(["i", "want"])
        store.speakStrip()
        XCTAssertEqual(player.lastSpeakSequence, ["i", "want"])
        XCTAssertEqual(player.lastSpeakAudioURLs, store.strip.cachedAudioURLs(using: cache))
        XCTAssertEqual(player.lastSpeakAudioURLs.map(\.lastPathComponent), ["audio.mp3", "audio.mp3"])
        XCTAssertTrue(player.lastSpeakAudioURLs[0].path.contains("/i/"))
        XCTAssertTrue(player.lastSpeakAudioURLs[1].path.contains("/want/"))

        profiles.switchTo(.child2, overlay: store, grid: grid)

        XCTAssertEqual(store.cards.map(\.slug), boardSlugs)
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        XCTAssertEqual(store.coreCards.map(\.word), ["I", "want", "more", "help", "stop", "go"])
        XCTAssertTrue(cache.hasAudio("i"))
        XCTAssertTrue(cache.hasAudio("want"))
        XCTAssertTrue(store.strip.isEmpty)

        store.hideAfterConfirm("ice-cream")
        store.appendSlugsFromBoard(["i", "want", "go"])
        store.speakStrip()
        XCTAssertEqual(player.lastSpeakSequence, ["i", "want", "go"])
        XCTAssertEqual(player.lastSpeakAudioURLs, store.strip.cachedAudioURLs(using: cache))
        XCTAssertEqual(player.lastSpeakAudioURLs.map(\.lastPathComponent), ["audio.mp3", "audio.mp3", "audio.mp3"])
        XCTAssertEqual(player.lastSpeakAudioURLs[0], cache.audioURL(for: "i"))
        XCTAssertEqual(player.lastSpeakAudioURLs[1], cache.audioURL(for: "want"))
        XCTAssertEqual(player.lastSpeakAudioURLs[2], cache.audioURL(for: "go"))

        profiles.switchTo(.child1, overlay: store, grid: grid)
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        XCTAssertEqual(store.hiddenSlugs, ["juice"])
        XCTAssertTrue(store.strip.isEmpty)

        store.appendSlugsFromBoard(["more", "help"])
        store.speakStrip()
        XCTAssertEqual(player.lastSpeakSequence, ["more", "help"])
        XCTAssertEqual(player.lastSpeakAudioURLs, [cache.audioURL(for: "more"), cache.audioURL(for: "help")])
        XCTAssertEqual(player.lastSpeakAudioURLs.map(\.lastPathComponent), ["audio.mp3", "audio.mp3"])
    }

    func testLaunchArgCallsTheSameSwitcher() throws {
        try seedBoard()
        store.hideAfterConfirm("juice")
        XCTAssertEqual(profiles.activeName, "Child 1")

        profiles.applyLaunchArguments(["-Profile", "Child 2"], overlay: store, grid: grid)

        XCTAssertEqual(profiles.activeName, "Child 2")
        XCTAssertEqual(store.activeProfile, .child2)
        XCTAssertEqual(defaults.string(forKey: ProfileStore.defaultsKey), "Child 2")
        XCTAssertFalse(store.hiddenSlugs.contains("juice"))
        XCTAssertTrue(store.strip.isEmpty)
    }

    func testSwitchDoesNotRequestProfilesEndpoint() throws {
        try seedBoard()
        FixtureURLProtocol.reset()
        FixtureURLProtocol.recorded = []

        profiles.switchTo(.child2, overlay: store, grid: grid)
        store.hideAfterConfirm("juice")
        profiles.switchTo(.child1, overlay: store, grid: grid)

        XCTAssertTrue(FixtureURLProtocol.requests.isEmpty)
        XCTAssertFalse(FixtureURLProtocol.requests.contains { $0.url?.path.contains("profiles") == true })
        XCTAssertEqual(store.cards.count, 8)
    }
}
