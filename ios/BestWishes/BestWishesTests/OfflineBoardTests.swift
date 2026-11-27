import XCTest
import UIKit
@testable import BestWishes

@MainActor
final class OfflineBoardTests: XCTestCase {
    private func card(_ word: String, slug: String? = nil) -> Card {
        let slug = slug ?? word.lowercased()
        return Card(
            word: word,
            slug: slug,
            imageURL: "/v1/cards/\(slug)/image",
            audioURL: "/v1/cards/\(slug)/audio"
        )
    }

    private func seedImage(_ cache: AssetCache, slug: String) throws {
        let dir = cache.directory(for: slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let data = renderer.pngData { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        try data.write(to: cache.imageURL(for: slug))
        XCTAssertTrue(cache.hasImage(slug))
        XCTAssertNotNil(cache.loadImage(slug))
    }

    private func seedAudio(_ cache: AssetCache, slug: String) throws {
        let dir = cache.directory(for: slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("BestWishes-test-mp3".utf8).write(to: cache.audioURL(for: slug))
        XCTAssertTrue(cache.hasAudio(slug))
    }

    /// Warm on-device cache, then a store whose shipped client cannot reach the host.
    private func makeWarmOfflineStore() throws -> (CardStore, SpeechPlayer, AssetCache, [Card]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-offline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = AssetCache(root: root)

        let i = card("I", slug: "i")
        let want = card("want")
        let juice = card("juice")
        let cards = [i, want, juice]
        let food = BoardFolder(id: "food", name: "Food", parentId: nil, memberSlugs: ["juice"])

        let warmer = CardStore(cache: cache, player: SpeechPlayer())
        warmer.seedLocalBoard(cards: cards, folders: [food])
        for item in cards {
            try seedImage(cache, slug: item.slug)
            try seedAudio(cache, slug: item.slug)
        }

        let api = APIClient(baseURL: APIClient.unreachableBaseURL)
        let player = SpeechPlayer()
        let store = CardStore(api: api, cache: cache, player: player)
        return (store, player, cache, cards)
    }

    private func failFast<T>(
        _ seconds: TimeInterval = 6,
        _ work: @escaping @MainActor () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { @MainActor in
                await work()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw NSError(
                    domain: "OfflineBoardTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "hung waiting for unreachable host"]
                )
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    func testLaunchArgPointsShippedClientAtUnreachableHost() {
        let client = APIClient.fromLaunchArguments(["-APIBaseURL", APIClient.unreachableBaseURL.absoluteString])
        XCTAssertEqual(client.baseURL, APIClient.unreachableBaseURL)
        let production = APIClient.fromLaunchArguments([])
        XCTAssertEqual(production.baseURL, APIClient.productionBaseURL)
    }

    func testFetchCardsOnUnreachableHostFailsFast() async throws {
        let api = APIClient(baseURL: APIClient.unreachableBaseURL)
        let started = Date()
        let reached = try await failFast(6) { () -> Bool in
            do {
                _ = try await api.fetchCards()
                return true
            } catch let error as APIError {
                XCTAssertEqual(error.errorDescription, "Could not reach Hope's Voice.")
                return false
            } catch {
                XCTFail("expected APIError.badURL, got \(error)")
                return false
            }
        }
        XCTAssertFalse(reached, "GET against an unreachable host must throw")
        XCTAssertLessThan(Date().timeIntervalSince(started), 6)
    }

    func testFetchBoardOnUnreachableHostFailsFast() async throws {
        let api = APIClient(baseURL: APIClient.unreachableBaseURL)
        let started = Date()
        let reached = try await failFast(6) { () -> Bool in
            do {
                _ = try await api.fetchBoard()
                return true
            } catch let error as APIError {
                XCTAssertEqual(error.errorDescription, "Could not reach Hope's Voice.")
                return false
            } catch {
                XCTFail("expected APIError.badURL, got \(error)")
                return false
            }
        }
        XCTAssertFalse(reached, "GET /v1/board against an unreachable host must throw")
        XCTAssertLessThan(Date().timeIntervalSince(started), 6)
    }

    func testBootstrapKeepsLastKnownCardsWhenGETFails() async throws {
        let (store, _, cache, seeded) = try makeWarmOfflineStore()
        let slugs = Set(seeded.map(\.slug))
        XCTAssertTrue(store.cards.isEmpty, "second store must start from disk, not already past fetch")

        try await failFast {
            await store.bootstrap()
        }

        XCTAssertFalse(store.cards.isEmpty)
        XCTAssertEqual(Set(store.cards.map(\.slug)), slugs)
        XCTAssertFalse(store.currentItems.isEmpty)
        XCTAssertEqual(store.banner, "Offline — showing saved cards.")
        XCTAssertNil(store.errorMessage)
        for item in seeded {
            XCTAssertTrue(cache.hasImage(item.slug), "GET failure must not wipe cached image for \(item.slug)")
            XCTAssertTrue(cache.hasAudio(item.slug), "GET failure must not wipe cached mp3 for \(item.slug)")
        }
        XCTAssertEqual(Set(cache.loadCachedCards().map(\.slug)), slugs)
    }

    func testSingleAndStripSpeakUseCachedMP3sWhenGETFails() async throws {
        let (store, player, cache, _) = try makeWarmOfflineStore()
        try await failFast {
            await store.bootstrap()
        }
        XCTAssertFalse(store.cards.isEmpty)

        guard let juice = store.cards.first(where: { $0.slug == "juice" }) else {
            XCTFail("warm cache must include juice")
            return
        }

        store.tap(juice)
        XCTAssertEqual(player.lastSpeakSequence, ["juice"])
        XCTAssertEqual(player.lastSpeakAudioURLs, [cache.audioURL(for: "juice")])
        XCTAssertTrue(cache.hasAudio("juice"))
        XCTAssertEqual(player.lastSpeakAudioURLs.first?.lastPathComponent, "audio.mp3")
        XCTAssertTrue(player.lastSpeakAudioURLs.first?.path.contains("/juice/") == true)

        store.clearStrip()
        store.appendSlugsFromBoard(["i", "want", "juice"])
        XCTAssertEqual(store.strip.slugs, ["i", "want", "juice"])

        store.speakStrip()
        XCTAssertEqual(player.lastSpeakSequence, ["i", "want", "juice"])
        XCTAssertEqual(
            player.lastSpeakAudioURLs,
            [cache.audioURL(for: "i"), cache.audioURL(for: "want"), cache.audioURL(for: "juice")]
        )
        XCTAssertEqual(player.lastSpeakAudioURLs, store.strip.cachedAudioURLs(using: cache))
        for url in player.lastSpeakAudioURLs {
            XCTAssertEqual(url.lastPathComponent, "audio.mp3")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testAddWordOfflineShowsErrorAndDoesNotAddCard() async throws {
        let (store, _, _, seeded) = try makeWarmOfflineStore()
        try await failFast {
            await store.bootstrap()
        }
        let slugsBefore = store.cards.map(\.slug)
        XCTAssertEqual(Set(slugsBefore), Set(seeded.map(\.slug)))

        try await failFast {
            await store.addWord("offline-word")
        }

        XCTAssertEqual(store.cards.map(\.slug), slugsBefore)
        XCTAssertFalse(store.cards.contains { $0.word == "offline-word" || $0.slug == "offline-word" })
        XCTAssertFalse(store.currentWordSlugs.contains("offline-word"))
        let message = try XCTUnwrap(store.errorMessage)
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(message, "Could not reach Hope's Voice.")
        XCTAssertNil(store.banner)
        XCTAssertFalse(store.isAdding)
    }
}
