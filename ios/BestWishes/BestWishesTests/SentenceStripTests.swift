import XCTest
@testable import BestWishes

@MainActor
final class SentenceStripTests: XCTestCase {
    private func card(_ word: String, slug: String? = nil) -> Card {
        let slug = slug ?? word.lowercased()
        return Card(
            word: word,
            slug: slug,
            imageURL: "/v1/cards/\(slug)/image",
            audioURL: "/v1/cards/\(slug)/audio"
        )
    }

    func testAppendOrderBackspaceAndClear() {
        var strip = SentenceStrip()
        XCTAssertTrue(strip.isEmpty)

        let first = card("I", slug: "i")
        let second = card("want", slug: "want")
        strip.append(first)
        strip.append(second)

        XCTAssertEqual(strip.slugs, [first.slug, second.slug])
        XCTAssertEqual(strip.cards, [first, second])

        strip.backspace()
        XCTAssertEqual(strip.slugs, [first.slug])
        XCTAssertEqual(strip.cards, [first])

        strip.clear()
        XCTAssertTrue(strip.isEmpty)
        XCTAssertEqual(strip.slugs, [])
    }

    func testCachedAudioURLsFollowStripOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-strip-\(UUID().uuidString)", isDirectory: true)
        let cache = AssetCache(root: root)
        var strip = SentenceStrip()
        let first = card("I", slug: "i")
        let second = card("juice", slug: "juice")
        strip.append(first)
        strip.append(second)

        let urls = strip.cachedAudioURLs(using: cache)
        XCTAssertEqual(urls, [cache.audioURL(for: first.slug), cache.audioURL(for: second.slug)])
        XCTAssertEqual(urls.map(\.lastPathComponent), ["audio.mp3", "audio.mp3"])
        XCTAssertTrue(urls[0].path.contains("/\(first.slug)/"))
        XCTAssertTrue(urls[1].path.contains("/\(second.slug)/"))
    }
}

@MainActor
final class CardStoreStripTests: XCTestCase {
    private func card(_ word: String, slug: String) -> Card {
        Card(
            word: word,
            slug: slug,
            imageURL: "/v1/cards/\(slug)/image",
            audioURL: "/v1/cards/\(slug)/audio"
        )
    }

    private func makeStore() throws -> (CardStore, SpeechPlayer, AssetCache) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = AssetCache(root: root)
        let player = SpeechPlayer()
        let store = CardStore(cache: cache, player: player)
        return (store, player, cache)
    }

    private func seedAudio(_ cache: AssetCache, slug: String) throws {
        let dir = cache.directory(for: slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("BestWishes-test-mp3".utf8).write(to: cache.audioURL(for: slug))
        XCTAssertTrue(cache.hasAudio(slug))
    }

    func testTapAppendsSpeakRequestsCachedAudioThenBackspaceAndClear() throws {
        let (store, player, cache) = try makeStore()
        XCTAssertTrue(store.strip.isEmpty)

        let first = card("I", slug: "i")
        let second = card("want", slug: "want")
        try seedAudio(cache, slug: first.slug)
        try seedAudio(cache, slug: second.slug)

        store.tap(first)
        store.tap(second)
        XCTAssertEqual(store.strip.slugs, [first.slug, second.slug])
        XCTAssertEqual(store.strip.cards, [first, second])

        store.speakStrip()
        XCTAssertEqual(player.lastSpeakSequence, [first.slug, second.slug])
        XCTAssertEqual(player.lastSpeakAudioURLs, [cache.audioURL(for: first.slug), cache.audioURL(for: second.slug)])
        XCTAssertEqual(player.lastSpeakAudioURLs, store.strip.cachedAudioURLs(using: cache))

        store.backspaceStrip()
        XCTAssertEqual(store.strip.slugs, [first.slug])
        XCTAssertEqual(store.strip.cards, [first])

        store.clearStrip()
        XCTAssertTrue(store.strip.isEmpty)
        XCTAssertEqual(store.strip.cards, [])
    }

    func testSpeakStripOnTwoCardsIsSequentialSlugOrder() throws {
        let (store, player, cache) = try makeStore()
        let first = card("I", slug: "i")
        let second = card("juice", slug: "juice")
        try seedAudio(cache, slug: first.slug)
        try seedAudio(cache, slug: second.slug)

        store.tap(first)
        store.tap(second)
        store.speakStrip()

        XCTAssertEqual(player.lastSpeakSequence.count, 2)
        XCTAssertEqual(player.lastSpeakSequence[0], first.slug)
        XCTAssertEqual(player.lastSpeakSequence[1], second.slug)
        XCTAssertEqual(player.lastSpeakAudioURLs[0], cache.audioURL(for: first.slug))
        XCTAssertEqual(player.lastSpeakAudioURLs[1], cache.audioURL(for: second.slug))
    }
}
