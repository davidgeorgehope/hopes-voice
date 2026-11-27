import XCTest
import UIKit
@testable import BestWishes

/// In-front-of-client fixture. Records the shipped APIClient's real URLRequests.
final class FixtureURLProtocol: URLProtocol {
    struct Recorded {
        let request: URLRequest
        let body: Data
    }

    nonisolated(unsafe) static var recorded: [Recorded] = []
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    static var requests: [URLRequest] { recorded.map(\.request) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.bodyData(from: request)
        Self.recorded.append(Recorded(request: request, body: body))
        do {
            guard let handler = Self.handler else {
                throw URLError(.notConnectedToInternet)
            }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://bestwishes.test")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        recorded = []
        handler = nil
    }

    static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 4096)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@MainActor
final class BoardContractTests: XCTestCase {
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-board-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return CardStore(api: makeAPI(), cache: AssetCache(root: root), player: SpeechPlayer())
    }

    private func seedPNG(_ cache: AssetCache, slug: String) throws {
        let dir = cache.directory(for: slug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let data = renderer.pngData { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        try data.write(to: cache.imageURL(for: slug))
        try Data("BestWishes-test-mp3".utf8).write(to: cache.audioURL(for: slug))
    }

    func testFetchBoardDecodesLiveShapedRootJSON() async throws {
        FixtureURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/board")
            XCTAssertNil(request.url?.query)
            return (200, Data(Self.rootJSON.utf8))
        }

        let board = try await makeAPI().fetchBoard()

        XCTAssertNil(board.folderId)
        XCTAssertEqual(board.count, 3)
        XCTAssertEqual(board.items.count, 3)

        let food = try XCTUnwrap(board.items.first { $0.kind == .folder })
        XCTAssertEqual(food.slug, "food")
        XCTAssertEqual(food.word, "Food")
        XCTAssertEqual(food.name, "Food")
        XCTAssertEqual(food.imageURL, "/system/folder.png")
        XCTAssertNil(food.audioURL)
        XCTAssertNil(food.folderId)
        XCTAssertEqual(food.children, ["juice", "ice-cream"])

        let want = try XCTUnwrap(board.items.first { $0.slug == "want" })
        XCTAssertEqual(want.kind, .word)
        XCTAssertEqual(want.word, "want")
        XCTAssertEqual(want.imageURL, "/assets/want/image.png")
        XCTAssertEqual(want.audioURL, "/assets/want/audio.mp3")
        XCTAssertNil(want.folderId)
        XCTAssertNil(want.children)

        XCTAssertFalse(board.items.contains { $0.slug == "juice" })
        XCTAssertFalse(board.items.contains { $0.slug == "ice-cream" })
    }

    func testFetchBoardFolderIdQueryDecodesFoodChildren() async throws {
        FixtureURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/board")
            XCTAssertEqual(request.url?.query, "folder_id=food")
            return (200, Data(Self.foodJSON.utf8))
        }

        let board = try await makeAPI().fetchBoard(folderId: "food")

        XCTAssertEqual(board.folderId, "food")
        XCTAssertEqual(board.count, 2)
        XCTAssertEqual(board.items.map(\.kind), [.word, .word])
        XCTAssertEqual(Set(board.items.map(\.slug)), Set(["juice", "ice-cream"]))
        let juice = try XCTUnwrap(board.items.first { $0.slug == "juice" })
        XCTAssertEqual(juice.word, "juice")
        XCTAssertEqual(juice.imageURL, "/assets/juice/image.png")
        XCTAssertEqual(juice.audioURL, "/assets/juice/audio.mp3")
        XCTAssertEqual(juice.folderId, "food")
        let ice = try XCTUnwrap(board.items.first { $0.slug == "ice-cream" })
        XCTAssertEqual(ice.word, "ice cream")
        XCTAssertEqual(ice.folderId, "food")
    }

    func testRefreshAppliesRootThenFoodChildrenViaShippedStore() async throws {
        FixtureURLProtocol.handler = Self.standardBoardHandler()
        let store = try makeStore()

        await store.refresh()

        XCTAssertTrue(store.currentFolderIds.contains("food"))
        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        XCTAssertFalse(store.currentWordSlugs.contains("juice"))
        XCTAssertFalse(store.currentWordSlugs.contains("ice-cream"))
        XCTAssertEqual(store.grouping.folder(id: "food")?.imageURL, "/system/folder.png")
        XCTAssertEqual(Set(store.grouping.folder(id: "food")?.memberSlugs ?? []), Set(["juice", "ice-cream"]))

        store.openFolder(id: "food")
        XCTAssertEqual(store.currentFolderName, "Food")
        XCTAssertEqual(Set(store.currentWordSlugs), Set(["juice", "ice-cream"]))
        XCTAssertFalse(store.currentWordSlugs.contains("want"))
        XCTAssertTrue(store.currentFolderIds.isEmpty)
    }

    func testHideDoesNotIssueDeleteAndUnhideRestores() async throws {
        FixtureURLProtocol.handler = Self.standardBoardHandler()
        let store = try makeStore()
        await store.refresh()
        FixtureURLProtocol.recorded = []

        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        store.hideAfterConfirm("want")

        XCTAssertFalse(store.currentWordSlugs.contains("want"))
        XCTAssertTrue(store.hiddenSlugs.contains("want"))
        XCTAssertTrue(store.cards.contains { $0.slug == "want" })
        XCTAssertEqual(store.hiddenListSlugs, ["want"])
        XCTAssertFalse(FixtureURLProtocol.requests.contains { $0.httpMethod == "DELETE" })
        XCTAssertTrue(FixtureURLProtocol.requests.isEmpty)

        store.unhide("want")
        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        XCTAssertTrue(store.hiddenCards.isEmpty)
        XCTAssertFalse(FixtureURLProtocol.requests.contains { $0.httpMethod == "DELETE" })
    }

    func testDeleteCardIssuesDeleteClearsAssetsAndIsGoneAfterRefresh() async throws {
        FixtureURLProtocol.handler = Self.standardBoardHandler()
        let store = try makeStore()
        await store.refresh()
        try seedPNG(store.cache, slug: "want")
        XCTAssertTrue(store.cache.hasImage("want"))
        XCTAssertTrue(store.cache.hasAudio("want"))
        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        FixtureURLProtocol.handler = Self.standardBoardHandler(rootWithout: ["want"])
        FixtureURLProtocol.recorded = []

        await store.deleteCardAfterConfirm("want")

        let deleted = FixtureURLProtocol.requests.filter { $0.httpMethod == "DELETE" }
        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(deleted.first?.url?.path, "/v1/cards/want")
        XCTAssertFalse(store.cache.hasImage("want"))
        XCTAssertFalse(store.cache.hasAudio("want"))
        XCTAssertFalse(store.cards.contains { $0.slug == "want" })
        XCTAssertFalse(store.currentWordSlugs.contains("want"))
        XCTAssertTrue(store.currentFolderIds.contains("food"))
        XCTAssertTrue(FixtureURLProtocol.requests.contains { $0.httpMethod == "GET" && $0.url?.path == "/v1/board" })
    }

    func testAddInsideFolderPostsFolderIdAndUsesReturnedSlug() async throws {
        FixtureURLProtocol.handler = Self.standardBoardHandler()
        let store = try makeStore()
        await store.refresh()
        store.openFolder(id: "food")
        FixtureURLProtocol.handler = Self.standardBoardHandler(extraFood: [Self.applePieItem])
        FixtureURLProtocol.recorded = []

        await store.addWord("Apple Pie")

        let posts = FixtureURLProtocol.recorded.filter { $0.request.httpMethod == "POST" && $0.request.url?.path == "/v1/cards" }
        XCTAssertEqual(posts.count, 1)
        let body = Self.json(posts[0].body)
        XCTAssertEqual(body["word"] as? String, "Apple Pie")
        XCTAssertEqual(body["folder_id"] as? String, "food")
        XCTAssertTrue(store.currentWordSlugs.contains("apple-pie"))
        XCTAssertFalse(store.currentWordSlugs.contains("apple pie"))
        XCTAssertTrue(store.cards.contains { $0.slug == "apple-pie" && $0.word == "Apple Pie" })
        XCTAssertTrue(store.currentWordSlugs.contains("juice"))
    }

    func testNewFolderPostsNameThenRefreshesBoard() async throws {
        FixtureURLProtocol.handler = Self.standardBoardHandler()
        let store = try makeStore()
        await store.refresh()
        FixtureURLProtocol.handler = Self.standardBoardHandler(extraRoot: [Self.toysFolderItem])
        FixtureURLProtocol.recorded = []

        await store.addFolder("Toys")

        let posts = FixtureURLProtocol.recorded.filter { $0.request.httpMethod == "POST" && $0.request.url?.path == "/v1/folders" }
        XCTAssertEqual(posts.count, 1)
        let body = Self.json(posts[0].body)
        XCTAssertEqual(body["name"] as? String, "Toys")
        XCTAssertNil(body["word"])
        XCTAssertTrue(store.currentFolderIds.contains("toys"))
        XCTAssertTrue(store.currentFolderIds.contains("food"))
        XCTAssertTrue(FixtureURLProtocol.requests.contains { $0.httpMethod == "GET" && $0.url?.path == "/v1/board" })
        XCTAssertEqual(store.grouping.folder(id: "toys")?.imageURL, "/system/folder.png")
    }

    func testDeleteFolderIssuesDeleteAndChildrenMoveToRootAfterRefresh() async throws {
        FixtureURLProtocol.handler = Self.standardBoardHandler()
        let store = try makeStore()
        await store.refresh()
        XCTAssertTrue(store.currentFolderIds.contains("food"))
        FixtureURLProtocol.handler = Self.standardBoardHandler(deleteFood: true)
        FixtureURLProtocol.recorded = []

        await store.deleteFolderAfterConfirm("food")

        let deleted = FixtureURLProtocol.requests.filter { $0.httpMethod == "DELETE" }
        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(deleted.first?.url?.path, "/v1/folders/food")
        XCTAssertFalse(store.currentFolderIds.contains("food"))
        XCTAssertTrue(store.currentWordSlugs.contains("juice"))
        XCTAssertTrue(store.currentWordSlugs.contains("ice-cream"))
        XCTAssertTrue(store.currentWordSlugs.contains("want"))
        XCTAssertTrue(store.isAtRoot)
    }

    // MARK: - Fixtures matching live GET /v1/board

    /// Representative CONTRACT v0.2.0 root (Food + root words; juice/ice-cream are children).
    static let rootJSON = """
    {
      "items": [
        {
          "kind": "folder",
          "word": "Food",
          "slug": "food",
          "name": "Food",
          "image_url": "/system/folder.png",
          "folder_id": null,
          "children": ["juice", "ice-cream"],
          "created_at": "2026-09-16T02:47:27.620828+00:00"
        },
        {
          "word": "Daddy",
          "slug": "daddy",
          "image_path": "/opt/bestwishes/data/cards/daddy/image.png",
          "image_url": "/assets/daddy/image.png",
          "audio_url": "/assets/daddy/audio.mp3",
          "created_at": "2026-09-16T00:47:00.603954+00:00",
          "kind": "word",
          "folder_id": null
        },
        {
          "word": "want",
          "slug": "want",
          "image_url": "/assets/want/image.png",
          "audio_url": "/assets/want/audio.mp3",
          "kind": "word",
          "folder_id": null
        }
      ],
      "folder_id": null,
      "count": 3
    }
    """

    static let foodJSON = """
    {
      "items": [
        {
          "word": "juice",
          "slug": "juice",
          "image_url": "/assets/juice/image.png",
          "audio_url": "/assets/juice/audio.mp3",
          "kind": "word",
          "folder_id": "food"
        },
        {
          "word": "ice cream",
          "slug": "ice-cream",
          "image_url": "/assets/ice-cream/image.png",
          "audio_url": "/assets/ice-cream/audio.mp3",
          "kind": "word",
          "folder_id": "food"
        }
      ],
      "folder_id": "food",
      "count": 2
    }
    """

    static let applePieItem = """
    {
      "word": "Apple Pie",
      "slug": "apple-pie",
      "image_url": "/assets/apple-pie/image.png",
      "audio_url": "/assets/apple-pie/audio.mp3",
      "kind": "word",
      "folder_id": "food"
    }
    """

    static let toysFolderItem = """
    {
      "kind": "folder",
      "word": "Toys",
      "slug": "toys",
      "name": "Toys",
      "image_url": "/system/folder.png",
      "folder_id": null,
      "children": []
    }
    """

    static func json(_ body: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }

    static func standardBoardHandler(
        extraRoot: [String] = [],
        extraFood: [String] = [],
        rootWithout: Set<String> = [],
        deleteFood: Bool = false
    ) -> (URLRequest) throws -> (Int, Data) {
        { request in
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? "GET"
            let folderId = URLComponents(url: request.url ?? URL(string: "https://bestwishes.test")!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "folder_id" }?.value

            if method == "GET", path.hasPrefix("/assets/") || path.hasPrefix("/system/") {
                return (200, Data("png".utf8))
            }

            if method == "POST", path == "/v1/cards" {
                return (200, Data("""
                {
                  "word": "Apple Pie",
                  "slug": "apple-pie",
                  "image_url": "/assets/apple-pie/image.png",
                  "audio_url": "/assets/apple-pie/audio.mp3",
                  "kind": "word",
                  "folder_id": "food"
                }
                """.utf8))
            }

            if method == "POST", path == "/v1/folders" {
                return (200, Data(Self.toysFolderItem.utf8))
            }

            if method == "DELETE", path.hasPrefix("/v1/cards/") || path.hasPrefix("/v1/folders/") {
                return (204, Data())
            }

            if method == "GET", path == "/v1/board", let folderId, folderId != "food" {
                let body = "{\"items\":[],\"folder_id\":\"\(folderId)\",\"count\":0}"
                return (200, Data(body.utf8))
            }

            if method == "GET", path == "/v1/board", folderId == "food" {
                if deleteFood {
                    return (200, Data("""
                    {"items":[],"folder_id":"food","count":0}
                    """.utf8))
                }
                var items = [
                    """
                    {"word":"juice","slug":"juice","image_url":"/assets/juice/image.png","audio_url":"/assets/juice/audio.mp3","kind":"word","folder_id":"food"}
                    """,
                    """
                    {"word":"ice cream","slug":"ice-cream","image_url":"/assets/ice-cream/image.png","audio_url":"/assets/ice-cream/audio.mp3","kind":"word","folder_id":"food"}
                    """
                ]
                items.append(contentsOf: extraFood)
                let body = "{\"items\":[\(items.joined(separator: ","))],\"folder_id\":\"food\",\"count\":\(items.count)}"
                return (200, Data(body.utf8))
            }

            if method == "GET", path == "/v1/board" {
                if deleteFood {
                    let body = """
                    {
                      "items": [
                        {"word":"juice","slug":"juice","image_url":"/assets/juice/image.png","audio_url":"/assets/juice/audio.mp3","kind":"word","folder_id":null},
                        {"word":"ice cream","slug":"ice-cream","image_url":"/assets/ice-cream/image.png","audio_url":"/assets/ice-cream/audio.mp3","kind":"word","folder_id":null},
                        {"word":"want","slug":"want","image_url":"/assets/want/image.png","audio_url":"/assets/want/audio.mp3","kind":"word","folder_id":null}
                      ],
                      "folder_id": null,
                      "count": 3
                    }
                    """
                    return (200, Data(body.utf8))
                }
                var items: [String] = [
                    """
                    {"kind":"folder","word":"Food","slug":"food","name":"Food","image_url":"/system/folder.png","folder_id":null,"children":["juice","ice-cream"]}
                    """
                ]
                if !rootWithout.contains("daddy") {
                    items.append("""
                    {"word":"Daddy","slug":"daddy","image_url":"/assets/daddy/image.png","audio_url":"/assets/daddy/audio.mp3","kind":"word","folder_id":null}
                    """)
                }
                if !rootWithout.contains("want") {
                    items.append("""
                    {"word":"want","slug":"want","image_url":"/assets/want/image.png","audio_url":"/assets/want/audio.mp3","kind":"word","folder_id":null}
                    """)
                }
                items.append(contentsOf: extraRoot)
                let body = "{\"items\":[\(items.joined(separator: ","))],\"folder_id\":null,\"count\":\(items.count)}"
                return (200, Data(body.utf8))
            }

            return (404, Data("{\"detail\":\"not mocked \(method) \(path)\"}".utf8))
        }
    }
}
