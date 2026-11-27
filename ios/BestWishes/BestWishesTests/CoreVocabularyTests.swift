import XCTest
@testable import BestWishes

@MainActor
final class CoreVocabularyTests: XCTestCase {
    private func card(_ word: String, slug: String? = nil) -> Card {
        let slug = slug ?? word.lowercased()
        return Card(
            word: word,
            slug: slug,
            imageURL: "/assets/\(slug)/image.png",
            audioURL: "/assets/\(slug)/audio.mp3"
        )
    }

    private func makeStore() throws -> (CardStore, SpeechPlayer, AssetCache) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = AssetCache(root: root)
        let player = SpeechPlayer()
        return (CardStore(cache: cache, player: player), player, cache)
    }

    private func seedAudio(_ cache: AssetCache, slug: String) throws {
        let dir = cache.directory(for: slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("BestWishes-test-mp3".utf8).write(to: cache.audioURL(for: slug))
        XCTAssertTrue(cache.hasAudio(slug))
    }

    private func seedCoreBoard(_ store: CardStore, cache: AssetCache) throws {
        let cores = CoreVocabulary.ordered.map { card($0.word, slug: $0.slug) }
        let juice = card("juice")
        let iceCream = card("ice cream", slug: "ice-cream")
        let food = BoardFolder(id: "food", name: "Food", parentId: nil, memberSlugs: ["juice", "ice-cream"])
        store.seedLocalBoard(cards: cores + [juice, iceCream], folders: [food])
        for item in cores + [juice, iceCream] {
            try seedAudio(cache, slug: item.slug)
        }
    }

    func testOrderedCoresStayAvailableAcrossFolderOpenBackAndHome() throws {
        let (store, _, cache) = try makeStore()
        try seedCoreBoard(store, cache: cache)

        XCTAssertEqual(CoreVocabulary.words, ["I", "want", "more", "help", "stop", "go"])
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        XCTAssertEqual(store.coreCards.map(\.word), ["I", "want", "more", "help", "stop", "go"])
        XCTAssertTrue(store.isAtRoot)
        XCTAssertTrue(store.currentFolderIds.contains("food"))

        store.openFolder(id: "food")
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertEqual(Set(store.currentWordSlugs), Set(["juice", "ice-cream"]))
        XCTAssertFalse(store.currentWordSlugs.contains("want"))
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        XCTAssertEqual(store.coreCards.map(\.word), ["I", "want", "more", "help", "stop", "go"])

        store.goBack()
        XCTAssertTrue(store.isAtRoot)
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])

        store.openFolder(id: "food")
        store.goHome()
        XCTAssertTrue(store.isAtRoot)
        XCTAssertNil(store.currentFolderName)
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        XCTAssertTrue(store.currentFolderIds.contains("food"))
    }

    func testTapCoreInsideFolderAppendsAndRequestsCachedMP3SameAsGridTap() throws {
        let (store, player, cache) = try makeStore()
        try seedCoreBoard(store, cache: cache)

        store.openFolder(id: "food")
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertTrue(store.strip.isEmpty)

        let i = try XCTUnwrap(store.coreCards.first { $0.slug == "i" })
        let want = try XCTUnwrap(store.coreCards.first { $0.slug == "want" })
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])

        store.tap(i)
        store.tapCore(want)
        XCTAssertEqual(store.strip.slugs, ["i", "want"])
        XCTAssertEqual(store.strip.cards, [i, want])
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertEqual(player.lastSpeakSequence, ["want"])
        XCTAssertEqual(player.lastSpeakAudioURLs, [cache.audioURL(for: "want")])
        XCTAssertEqual(player.lastSpeakAudioURLs.first?.lastPathComponent, "audio.mp3")
        XCTAssertTrue(player.lastSpeakAudioURLs.first?.path.contains("/want/") == true)

        guard case .word(let juice) = store.currentItems.first(where: {
            if case .word(let card) = $0 { return card.slug == "juice" }
            return false
        }) else {
            XCTFail("Food folder must show juice")
            return
        }
        store.tap(juice)
        XCTAssertEqual(store.strip.slugs, ["i", "want", "juice"])
        XCTAssertEqual(player.lastSpeakSequence, ["juice"])
        XCTAssertEqual(player.lastSpeakAudioURLs, [cache.audioURL(for: "juice")])
    }

    func testHideDoesNotRemoveCoreFromStripRow() throws {
        let (store, _, cache) = try makeStore()
        try seedCoreBoard(store, cache: cache)

        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        store.hideAfterConfirm("want")
        XCTAssertFalse(store.currentWordSlugs.contains("want"))
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        XCTAssertTrue(store.coreCards.contains { $0.slug == "want" })
    }
}

@MainActor
final class CoreVocabularyBootstrapTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        FixtureURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureURLProtocol.self]
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 4
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        FixtureURLProtocol.reset()
        super.tearDown()
    }

    private func makeAPI() -> APIClient {
        APIClient(baseURL: URL(string: "https://bestwishes.test")!, session: session)
    }

    private func makeStore() throws -> CardStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-core-boot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return CardStore(api: makeAPI(), cache: AssetCache(root: root), player: SpeechPlayer())
    }

    func testEnsureDoesNotPostWhenAllCoresAlreadyOnBoard() async throws {
        FixtureURLProtocol.handler = Self.handler(rootCoreSlugs: CoreVocabulary.slugs)
        let store = try makeStore()

        await store.refresh()
        FixtureURLProtocol.recorded = []
        await store.ensureCoreVocabulary()

        let posts = FixtureURLProtocol.recorded.filter {
            $0.request.httpMethod == "POST" && $0.request.url?.path == "/v1/cards"
        }
        XCTAssertTrue(posts.isEmpty, "must not POST cores that GET already returned")
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        XCTAssertEqual(store.coreCards.map(\.word), ["I", "want", "more", "help", "stop", "go"])
    }

    func testEnsurePostsMissingCoresToRootWithNoFolderId() async throws {
        FixtureURLProtocol.handler = Self.handler(rootCoreSlugs: ["want"])
        let store = try makeStore()

        await store.bootstrap()

        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        XCTAssertEqual(store.coreCards.map(\.word), ["I", "want", "more", "help", "stop", "go"])

        let posts = FixtureURLProtocol.recorded.filter {
            $0.request.httpMethod == "POST" && $0.request.url?.path == "/v1/cards"
        }
        XCTAssertEqual(posts.count, 5)
        let postedWords = posts.map { Self.json($0.body)["word"] as? String }
        XCTAssertEqual(Set(postedWords.compactMap { $0 }), Set(["I", "more", "help", "stop", "go"]))
        for post in posts {
            let body = Self.json(post.body)
            XCTAssertNil(body["folder_id"], "core bootstrap POSTs to root")
            XCTAssertNotNil(body["word"])
        }

        store.openFolder(id: "food")
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        XCTAssertFalse(store.currentWordSlugs.contains("want"))
    }

    func testOfflineBootstrapDoesNotPostCores() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-core-off-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = AssetCache(root: root)
        let cores = CoreVocabulary.ordered.map {
            Card(word: $0.word, slug: $0.slug, imageURL: "/assets/\($0.slug)/image.png", audioURL: "/assets/\($0.slug)/audio.mp3")
        }
        let warmer = CardStore(cache: cache, player: SpeechPlayer())
        warmer.seedLocalBoard(
            cards: cores,
            folders: [BoardFolder(id: "food", name: "Food", parentId: nil, memberSlugs: [])]
        )

        let store = CardStore(api: APIClient(baseURL: APIClient.unreachableBaseURL), cache: cache, player: SpeechPlayer())
        await store.bootstrap()

        XCTAssertFalse(store.lastBoardFetchSucceeded)
        XCTAssertEqual(store.coreSlugs, ["i", "want", "more", "help", "stop", "go"])
        XCTAssertEqual(store.banner, "Offline — showing saved cards.")
    }

    private static func json(_ body: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }

    private static func handler(rootCoreSlugs: [String]) -> (URLRequest) throws -> (Int, Data) {
        { request in
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? "GET"
            let folderId = URLComponents(url: request.url ?? URL(string: "https://bestwishes.test")!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "folder_id" }?.value

            if method == "GET", path.hasPrefix("/assets/") || path.hasPrefix("/system/") {
                return (200, Data("png".utf8))
            }

            if method == "POST", path == "/v1/cards" {
                let body = Self.json(FixtureURLProtocol.bodyData(from: request))
                XCTAssertNil(body["folder_id"])
                let word = body["word"] as? String ?? ""
                let slug = word.lowercased().filter(\.isLetter)
                let json = """
                {"word":"\(word)","slug":"\(slug)","image_url":"/assets/\(slug)/image.png","audio_url":"/assets/\(slug)/audio.mp3","kind":"word","folder_id":null}
                """
                return (200, Data(json.utf8))
            }

            if method == "GET", path == "/v1/cards" {
                let items = rootCoreSlugs.map { slug in
                    let word = CoreVocabulary.ordered.first { $0.slug == slug }?.word ?? slug
                    return """
                    {"word":"\(word)","slug":"\(slug)","image_url":"/assets/\(slug)/image.png","audio_url":"/assets/\(slug)/audio.mp3","kind":"word","folder_id":null}
                    """
                }
                let body = "{\"cards\":[\(items.joined(separator: ","))],\"count\":\(items.count)}"
                return (200, Data(body.utf8))
            }

            if method == "GET", path == "/v1/board", folderId == "food" {
                return (200, Data("""
                {"items":[
                  {"word":"juice","slug":"juice","image_url":"/assets/juice/image.png","audio_url":"/assets/juice/audio.mp3","kind":"word","folder_id":"food"},
                  {"word":"ice cream","slug":"ice-cream","image_url":"/assets/ice-cream/image.png","audio_url":"/assets/ice-cream/audio.mp3","kind":"word","folder_id":"food"}
                ],"folder_id":"food","count":2}
                """.utf8))
            }

            if method == "GET", path == "/v1/board" {
                var items: [String] = [
                    """
                    {"kind":"folder","word":"Food","slug":"food","name":"Food","image_url":"/system/folder.png","folder_id":null,"children":["juice","ice-cream"]}
                    """
                ]
                for slug in rootCoreSlugs {
                    let word = CoreVocabulary.ordered.first { $0.slug == slug }?.word ?? slug
                    items.append("""
                    {"word":"\(word)","slug":"\(slug)","image_url":"/assets/\(slug)/image.png","audio_url":"/assets/\(slug)/audio.mp3","kind":"word","folder_id":null}
                    """)
                }
                let body = "{\"items\":[\(items.joined(separator: ","))],\"folder_id\":null,\"count\":\(items.count)}"
                return (200, Data(body.utf8))
            }

            return (404, Data("{\"detail\":\"not mocked \(method) \(path)\"}".utf8))
        }
    }
}
