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
        let extras = ["mommy", "car", "ball", "cookie", "milk"].map { card($0) }
        let food = BoardFolder(id: "food", name: "Food", parentId: nil, memberSlugs: ["juice", "ice-cream"])
        store.seedLocalBoard(cards: cores + [juice, iceCream, daddy] + extras, folders: [food])
        for item in cores + [juice, iceCream, daddy] + extras {
            try seedAudio(cache, slug: item.slug)
        }
    }

    private func cardFromStore(_ store: CardStore, slug: String) throws -> Card {
        try XCTUnwrap(store.cards.first { $0.slug == slug })
    }

    func testRecentsAreMostRecentFirstUniqueCappedAt6AndNeverRepeatCoreWords() throws {
        let (store, player, cache) = try makeStore()
        try seedBoard(store, cache: cache)

        XCTAssertTrue(store.recentSlugs.isEmpty)
        XCTAssertTrue(store.recentCards.isEmpty)
        XCTAssertEqual(CardStore.recentsLimit, 6)

        let want = try cardFromStore(store, slug: "want")
        let juice = try cardFromStore(store, slug: "juice")
        let more = try cardFromStore(store, slug: "more")

        store.tap(want)
        XCTAssertTrue(store.recentSlugs.isEmpty, "core-row words never go to Recents")
        XCTAssertEqual(store.strip.slugs, ["want"])
        XCTAssertEqual(player.lastSpeakSequence, ["want"])
        XCTAssertEqual(player.lastSpeakAudioURLs, [cache.audioURL(for: "want")])
        XCTAssertEqual(player.lastSpeakAudioURLs.first?.lastPathComponent, "audio.mp3")

        store.tap(juice)
        XCTAssertEqual(store.recentSlugs, ["juice"])

        store.tapCore(more)
        XCTAssertEqual(store.recentSlugs, ["juice"])
        XCTAssertEqual(store.recentCards.map(\.slug), ["juice"])

        store.tap(juice)
        XCTAssertEqual(store.recentSlugs, ["juice"])

        let spoken: [String] = ["i", "want", "more", "help", "stop", "go", "juice", "ice-cream", "daddy",
                                "mommy", "car", "ball", "cookie", "milk", "car"]
        for slug in spoken {
            store.tap(try cardFromStore(store, slug: slug))
        }
        XCTAssertEqual(store.recentSlugs.count, CardStore.recentsLimit)
        XCTAssertEqual(store.recentSlugs, ["car", "milk", "cookie", "ball", "mommy", "daddy"])
        XCTAssertEqual(Set(store.recentSlugs).count, store.recentSlugs.count, "no duplicates")
        XCTAssertTrue(Set(store.recentSlugs).isDisjoint(with: CoreVocabulary.slugs))
        XCTAssertLessThanOrEqual(store.recentCards.count, CardStore.recentsLimit)
        XCTAssertEqual(store.recentCards.map(\.slug), store.recentSlugs)
    }

    func testRecentsNeverGrowPastTheCapNoMatterHowMuchIsSpoken() throws {
        let (store, _, cache) = try makeStore()
        try seedBoard(store, cache: cache)
        let words = ["juice", "ice-cream", "daddy", "mommy", "car", "ball", "cookie", "milk"]
        for round in 0..<50 {
            store.tap(try cardFromStore(store, slug: words[round % words.count]))
            XCTAssertLessThanOrEqual(store.recentSlugs.count, CardStore.recentsLimit)
        }
        XCTAssertEqual(cache.loadRecents(for: .child1).count, CardStore.recentsLimit)
        let file = try Data(contentsOf: cache.recentsFileURL(for: .child1))
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: file).count, CardStore.recentsLimit)
    }

    func testRecentsSurviveRelaunchWithTheSameCap() throws {
        let cache = try makeCache()
        let (store, _, _) = try makeStore(cache: cache)
        try seedBoard(store, cache: cache)
        for slug in ["juice", "ice-cream", "daddy", "mommy", "car", "ball", "cookie", "milk"] {
            store.tap(try cardFromStore(store, slug: slug))
        }
        let expected = ["milk", "cookie", "ball", "car", "mommy", "daddy"]
        XCTAssertEqual(store.recentSlugs, expected)

        let reopened = CardStore(cache: cache, player: SpeechPlayer(), profile: .child1)
        try seedBoard(reopened, cache: cache)
        XCTAssertEqual(reopened.recentSlugs, expected)
        XCTAssertEqual(reopened.recentCards.map(\.slug), expected)
    }

    func testOldRecentsFileWithEightEntriesCoreWordsAndDuplicatesIsTrimmedOnLoad() throws {
        let cache = try makeCache()
        let legacy = ["i", "juice", "want", "juice", "daddy", "mommy", "car", "ball", "cookie", "milk", "go"]
        try JSONEncoder().encode(legacy).write(to: cache.recentsFileURL(for: .child1), options: .atomic)
        XCTAssertEqual(cache.loadRecents(for: .child1), ["juice", "daddy", "mommy", "car", "ball", "cookie"])

        let (store, _, _) = try makeStore(cache: cache)
        XCTAssertEqual(store.recentSlugs, ["juice", "daddy", "mommy", "car", "ball", "cookie"])
        XCTAssertEqual(store.recentSlugs.count, CardStore.recentsLimit)
    }

    func testSanitizedRecentsRules() {
        XCTAssertEqual(CardStore.sanitizedRecents([]), [])
        XCTAssertEqual(CardStore.sanitizedRecents(["", "a", "a", "b"]), ["a", "b"])
        XCTAssertEqual(CardStore.sanitizedRecents(["i", "want", "more", "help", "stop", "go"]), [])
        XCTAssertEqual(
            CardStore.sanitizedRecents((0..<20).map { "w\($0)" }),
            (0..<CardStore.recentsLimit).map { "w\($0)" }
        )
    }

    func testRecentsOffHidesTheRowButStillRemembersWords() throws {
        let (store, _, cache) = try makeStore()
        try seedBoard(store, cache: cache)
        store.settings.showRecents = false
        store.tap(try cardFromStore(store, slug: "juice"))
        XCTAssertTrue(store.recentCards.isEmpty)
        store.settings.showRecents = true
        XCTAssertEqual(store.recentCards.map(\.slug), ["juice"])
    }

    func testImportedBoardsStartWithRecentsOff() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.board.json")
        let document = try BoardImport.decode(Data(contentsOf: url))
        XCTAssertFalse(ProfileSettings.fromImport(document.profile).showRecents)
        XCTAssertTrue(ProfileSettings.default.showRecents, "the built-in board keeps Recents on")
    }

    func testSpeakStripRecordsLastSpokenFirst() throws {
        let (store, player, cache) = try makeStore()
        try seedBoard(store, cache: cache)

        store.appendSlugsFromBoard(["i", "want", "juice"])
        XCTAssertEqual(store.strip.slugs, ["i", "want", "juice"])
        XCTAssertTrue(store.recentSlugs.isEmpty, "append without Speak must not count")

        store.speakStrip()
        XCTAssertEqual(store.recentSlugs, ["juice"])
        XCTAssertEqual(store.recentCards.map(\.word), ["juice"])
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
        XCTAssertEqual(store.recentSlugs, ["juice"])
        XCTAssertEqual(store.strip.slugs, ["want", "juice"])

        store.clearStrip()
        XCTAssertTrue(store.strip.isEmpty)
        XCTAssertEqual(store.recentSlugs, ["juice"], "Clear must not wipe Recents")

        let recentJuice = try XCTUnwrap(store.recentCards.first { $0.slug == "juice" })
        store.tapRecent(recentJuice)

        XCTAssertEqual(store.strip.slugs, ["juice"])
        XCTAssertEqual(store.strip.cards.map(\.slug), ["juice"])
        XCTAssertEqual(store.recentSlugs, ["juice"])
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
        store.tap(try cardFromStore(store, slug: "daddy"))
        XCTAssertEqual(store.recentSlugs, ["daddy", "juice"])
        XCTAssertEqual(store.strip.slugs, ["juice", "daddy"])
        XCTAssertEqual(cache.loadRecents(for: .child1), ["daddy", "juice"])

        profiles.switchTo(.child2, overlay: store, grid: grid)

        XCTAssertEqual(store.activeProfile, .child2)
        XCTAssertTrue(store.strip.isEmpty)
        XCTAssertTrue(store.recentSlugs.isEmpty)
        XCTAssertNotEqual(store.recentSlugs, ["daddy", "juice"])

        store.tap(try cardFromStore(store, slug: "mommy"))
        store.tap(try cardFromStore(store, slug: "car"))
        XCTAssertEqual(store.recentSlugs, ["car", "mommy"])
        XCTAssertNotEqual(store.recentSlugs, cache.loadRecents(for: .child1))
        XCTAssertEqual(cache.loadRecents(for: .child1), ["daddy", "juice"])
        XCTAssertEqual(cache.loadRecents(for: .child2), ["car", "mommy"])

        profiles.switchTo(.child1, overlay: store, grid: grid)
        XCTAssertEqual(store.activeProfile, .child1)
        XCTAssertTrue(store.strip.isEmpty)
        XCTAssertEqual(store.recentSlugs, ["daddy", "juice"])
        XCTAssertNotEqual(store.recentSlugs, ["car", "mommy"])

        let reopenedChild1 = CardStore(cache: cache, player: SpeechPlayer(), profile: .child1)
        try seedBoard(reopenedChild1, cache: cache)
        XCTAssertEqual(reopenedChild1.recentSlugs, ["daddy", "juice"])
        XCTAssertEqual(reopenedChild1.recentCards.map(\.slug), ["daddy", "juice"])

        let reopenedChild2 = CardStore(cache: cache, player: SpeechPlayer(), profile: .child2)
        try seedBoard(reopenedChild2, cache: cache)
        XCTAssertEqual(reopenedChild2.recentSlugs, ["car", "mommy"])
        XCTAssertNotEqual(reopenedChild1.recentSlugs, reopenedChild2.recentSlugs)
        XCTAssertEqual(reopenedChild2.recentCards.map(\.slug), ["car", "mommy"])
    }
}
