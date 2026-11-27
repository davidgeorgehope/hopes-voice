import XCTest
@testable import BestWishes

@MainActor
final class RecentsTests: XCTestCase {
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-recents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return AssetCache(root: root)
    }

    private func makeStore(cache: AssetCache? = nil, profile: KidProfile = .child1) throws -> (CardStore, SpeechPlayer, AssetCache) {
        let cache = try cache ?? makeCache()
        let player = SpeechPlayer()
        return (CardStore(cache: cache, player: player, profile: profile), player, cache)
    }

    private func seedAudio(_ cache: AssetCache, slug: String) throws {
        let dir = cache.directory(for: slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("BestWishes-test-mp3".utf8).write(to: cache.audioURL(for: slug))
        XCTAssertTrue(cache.hasAudio(slug))
    }

    private func seedBoard(_ store: CardStore, cache: AssetCache) throws {
        let cores = CoreVocabulary.ordered.map { card($0.word, slug: $0.slug) }
        let juice = card("juice")
        let iceCream = card("ice cream", slug: "ice-cream")
        let daddy = card("Daddy", slug: "daddy")
        let food = BoardFolder(id: "food", name: "Food", parentId: nil, memberSlugs: ["juice", "ice-cream"])
        store.seedLocalBoard(cards: cores + [juice, iceCream, daddy], folders: [food])
        for item in cores + [juice, iceCream, daddy] {
            try seedAudio(cache, slug: item.slug)
        }
    }

    private func cardFromStore(_ store: CardStore, slug: String) throws -> Card {
        try XCTUnwrap(store.cards.first { $0.slug == slug })
    }

    func testGridTapAndCoreTapUpdateRecentsMostRecentFirstUniqueBySlugCap8() throws {
        let (store, player, cache) = try makeStore()
        try seedBoard(store, cache: cache)

        XCTAssertTrue(store.recentSlugs.isEmpty)
        XCTAssertTrue(store.recentCards.isEmpty)
        XCTAssertEqual(CardStore.recentsLimit, 8)

        let want = try cardFromStore(store, slug: "want")
        let juice = try cardFromStore(store, slug: "juice")
        let more = try cardFromStore(store, slug: "more")

        store.tap(want)
        XCTAssertEqual(store.recentSlugs, ["want"])
        XCTAssertEqual(store.strip.slugs, ["want"])
        XCTAssertEqual(player.lastSpeakSequence, ["want"])
        XCTAssertEqual(player.lastSpeakAudioURLs, [cache.audioURL(for: "want")])
        XCTAssertEqual(player.lastSpeakAudioURLs.first?.lastPathComponent, "audio.mp3")

        store.tap(juice)
        XCTAssertEqual(store.recentSlugs, ["juice", "want"])

        store.tapCore(more)
        XCTAssertEqual(store.recentSlugs, ["more", "juice", "want"])
        XCTAssertEqual(store.recentCards.map(\.slug), ["more", "juice", "want"])

        store.tap(juice)
        XCTAssertEqual(store.recentSlugs, ["juice", "more", "want"])
        XCTAssertEqual(store.recentSlugs.filter { $0 == "juice" }.count, 1)

        let spoken: [String] = ["i", "want", "more", "help", "stop", "go", "juice", "ice-cream", "daddy"]
        for slug in spoken {
            store.tap(try cardFromStore(store, slug: slug))
        }
        XCTAssertEqual(store.recentSlugs.count, 8)
        XCTAssertEqual(store.recentSlugs, Array(spoken.reversed().prefix(8)))
        XCTAssertFalse(store.recentSlugs.contains("i"))
        XCTAssertEqual(store.recentSlugs.first, "daddy")
        XCTAssertEqual(store.recentSlugs.last, "want")
    }

    func testSpeakStripRecordsLastSpokenFirst() throws {
        let (store, player, cache) = try makeStore()
        try seedBoard(store, cache: cache)

        store.appendSlugsFromBoard(["i", "want", "juice"])
        XCTAssertEqual(store.strip.slugs, ["i", "want", "juice"])
        XCTAssertTrue(store.recentSlugs.isEmpty, "append without Speak must not count")

        store.speakStrip()
        XCTAssertEqual(store.recentSlugs, ["juice", "want", "i"])
        XCTAssertEqual(store.recentCards.map(\.word), ["juice", "want", "I"])
        XCTAssertEqual(player.lastSpeakSequence, ["i", "want", "juice"])
        XCTAssertEqual(player.lastSpeakAudioURLs, [
            cache.audioURL(for: "i"),
            cache.audioURL(for: "want"),
            cache.audioURL(for: "juice"),
        ])
        XCTAssertEqual(player.lastSpeakAudioURLs.map(\.lastPathComponent), ["audio.mp3", "audio.mp3", "audio.mp3"])
    }

    func testFolderTapDoesNotCountTowardRecents() throws {
        let (store, _, cache) = try makeStore()
        try seedBoard(store, cache: cache)

        let food = try XCTUnwrap(store.grouping.folder(id: "food"))
        store.select(.folder(food))
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertTrue(store.recentSlugs.isEmpty)
        XCTAssertTrue(store.strip.isEmpty)

        let juice = try cardFromStore(store, slug: "juice")
        store.tap(juice)
        XCTAssertEqual(store.recentSlugs, ["juice"])

        store.goHome()
        store.select(.folder(food))
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertEqual(store.recentSlugs, ["juice"])
        XCTAssertEqual(store.recentCards.map(\.slug), ["juice"])
    }

    func testTapRecentReaddsToStripAndRequestsCachedMP3() throws {
        let (store, player, cache) = try makeStore()
        try seedBoard(store, cache: cache)

        let want = try cardFromStore(store, slug: "want")
        let juice = try cardFromStore(store, slug: "juice")
        store.tap(want)
        store.tap(juice)
        XCTAssertEqual(store.recentSlugs, ["juice", "want"])
        XCTAssertEqual(store.strip.slugs, ["want", "juice"])

        store.clearStrip()
        XCTAssertTrue(store.strip.isEmpty)
        XCTAssertEqual(store.recentSlugs, ["juice", "want"], "Clear must not wipe Recents")

        let recentJuice = try XCTUnwrap(store.recentCards.first { $0.slug == "juice" })
        store.tapRecent(recentJuice)

        XCTAssertEqual(store.strip.slugs, ["juice"])
        XCTAssertEqual(store.strip.cards.map(\.slug), ["juice"])
        XCTAssertEqual(store.recentSlugs, ["juice", "want"])
        XCTAssertEqual(player.lastSpeakSequence, ["juice"])
        XCTAssertEqual(player.lastSpeakAudioURLs, [cache.audioURL(for: "juice")])
        XCTAssertEqual(player.lastSpeakAudioURLs.first?.lastPathComponent, "audio.mp3")
        XCTAssertTrue(player.lastSpeakAudioURLs.first?.path.contains("/juice/") == true)
        XCTAssertEqual(player.lastSpeakAudioURLs.first, cache.audioURL(for: "juice"))
    }

    func testChild1RecentsDivergeFromChild2AfterSwitchAndReopen() throws {
        let cache = try makeCache()
        let suiteName = "bw-recents-profile-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profiles = ProfileStore(defaults: defaults)
        let player = SpeechPlayer()
        let store = CardStore(cache: cache, player: player, profile: profiles.active)
        let grid = GridLayout(defaults: defaults, profile: profiles.active)
        try seedBoard(store, cache: cache)
        XCTAssertEqual(store.activeProfile, .child1)

        store.tap(try cardFromStore(store, slug: "juice"))
        store.tap(try cardFromStore(store, slug: "want"))
        XCTAssertEqual(store.recentSlugs, ["want", "juice"])
        XCTAssertEqual(store.strip.slugs, ["juice", "want"])
        XCTAssertEqual(cache.loadRecents(for: .child1), ["want", "juice"])

        profiles.switchTo(.child2, overlay: store, grid: grid)

        XCTAssertEqual(store.activeProfile, .child2)
        XCTAssertTrue(store.strip.isEmpty)
        XCTAssertTrue(store.recentSlugs.isEmpty)
        XCTAssertNotEqual(store.recentSlugs, ["want", "juice"])

        store.tap(try cardFromStore(store, slug: "i"))
        store.tap(try cardFromStore(store, slug: "more"))
        XCTAssertEqual(store.recentSlugs, ["more", "i"])
        XCTAssertNotEqual(store.recentSlugs, cache.loadRecents(for: .child1))
        XCTAssertEqual(cache.loadRecents(for: .child1), ["want", "juice"])
        XCTAssertEqual(cache.loadRecents(for: .child2), ["more", "i"])

        profiles.switchTo(.child1, overlay: store, grid: grid)
        XCTAssertEqual(store.activeProfile, .child1)
        XCTAssertTrue(store.strip.isEmpty)
        XCTAssertEqual(store.recentSlugs, ["want", "juice"])
        XCTAssertNotEqual(store.recentSlugs, ["more", "i"])

        let reopenedChild1 = CardStore(cache: cache, player: SpeechPlayer(), profile: .child1)
        try seedBoard(reopenedChild1, cache: cache)
        XCTAssertEqual(reopenedChild1.recentSlugs, ["want", "juice"])
        XCTAssertEqual(reopenedChild1.recentCards.map(\.slug), ["want", "juice"])

        let reopenedChild2 = CardStore(cache: cache, player: SpeechPlayer(), profile: .child2)
        try seedBoard(reopenedChild2, cache: cache)
        XCTAssertEqual(reopenedChild2.recentSlugs, ["more", "i"])
        XCTAssertNotEqual(reopenedChild1.recentSlugs, reopenedChild2.recentSlugs)
        XCTAssertEqual(reopenedChild2.recentCards.map(\.slug), ["more", "i"])
    }
}
