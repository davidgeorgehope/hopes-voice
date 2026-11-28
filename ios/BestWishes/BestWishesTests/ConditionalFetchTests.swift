import XCTest
import UIKit
@testable import BestWishes

/// Serves canned responses with headers, and records the request headers it was sent.
final class ConditionalURLProtocol: URLProtocol {
    struct Reply {
        var status: Int
        var headers: [String: String] = [:]
        var body: Data = Data()
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> Reply)?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        handler = nil
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let reply = Self.handler?(request) ?? Reply(status: 500)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://hopes.test")!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Issue #27: only fetch what changed. Boards revalidate with If-None-Match; pictures and
/// voices that are already on disk are never downloaded again unless the server says they changed.
@MainActor
final class ConditionalFetchTests: XCTestCase {
    private var session: URLSession!
    private var root: URL!

    private static let boardJSON = """
    {"items":[{"kind":"word","slug":"juice","word":"juice","image_url":"/assets/juice/image.png","audio_url":"/assets/juice/audio.mp3"}],"folder_id":null,"count":1}
    """

    override func setUpWithError() throws {
        ConditionalURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConditionalURLProtocol.self]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 4
        session = URLSession(configuration: config)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-cond-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        ConditionalURLProtocol.reset()
        try? FileManager.default.removeItem(at: root)
    }

    private func makeAPI() -> APIClient {
        APIClient(baseURL: URL(string: "https://hopes.test")!, session: session)
    }

    private func headerValue(_ request: URLRequest, _ name: String) -> String? {
        request.value(forHTTPHeaderField: name)
    }

    // MARK: Board

    func testBoardFetchSendsValidatorAndReadsETag() async throws {
        ConditionalURLProtocol.handler = { request in
            if self.headerValue(request, "If-None-Match") == "\"v1\"" {
                return .init(status: 304, headers: ["ETag": "\"v1\""])
            }
            return .init(status: 200, headers: ["ETag": "\"v1\""], body: Data(Self.boardJSON.utf8))
        }
        let api = makeAPI()

        guard case .modified(let board, let etag) = try await api.fetchBoard(folderId: nil, ifNoneMatch: nil) else {
            return XCTFail("first fetch should return the board")
        }
        XCTAssertEqual(board.items.count, 1)
        XCTAssertEqual(etag, "\"v1\"")

        guard case .notModified = try await api.fetchBoard(folderId: nil, ifNoneMatch: etag) else {
            return XCTFail("matching validator should give 304")
        }
        XCTAssertNil(headerValue(ConditionalURLProtocol.requests[0], "If-None-Match"))
        XCTAssertEqual(headerValue(ConditionalURLProtocol.requests[1], "If-None-Match"), "\"v1\"")
    }

    func testRefreshRevalidatesAndKeepsTheBoardOnA304() async throws {
        ConditionalURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/v1/board" {
                if self.headerValue(request, "If-None-Match") == "\"v1\"" {
                    return .init(status: 304, headers: ["ETag": "\"v1\""])
                }
                return .init(status: 200, headers: ["ETag": "\"v1\""], body: Data(Self.boardJSON.utf8))
            }
            return .init(status: 304) // assets: pretend they are current
        }
        let cache = AssetCache(root: root)
        let store = CardStore(api: makeAPI(), cache: cache, player: SpeechPlayer(), thumbnails: ThumbnailCache())

        await store.refresh()
        XCTAssertEqual(store.cards.map(\.slug), ["juice"])
        XCTAssertEqual(cache.boardETag(folderId: nil), "\"v1\"")

        ConditionalURLProtocol.requests = []
        await store.refresh()
        let boardRequests = ConditionalURLProtocol.requests.filter { $0.url?.path == "/v1/board" }
        XCTAssertEqual(boardRequests.count, 1)
        XCTAssertEqual(headerValue(boardRequests[0], "If-None-Match"), "\"v1\"", "second refresh must be conditional")
        XCTAssertEqual(store.cards.map(\.slug), ["juice"], "a 304 leaves the board exactly as it was")
        XCTAssertNil(store.errorMessage)
    }

    func testChangedBoardReplacesTheCachedOneAndTheValidator() async throws {
        var version = 1
        ConditionalURLProtocol.handler = { request in
            guard request.url?.path == "/v1/board" else { return .init(status: 304) }
            let json = version == 1 ? Self.boardJSON : Self.boardJSON.replacingOccurrences(of: "juice", with: "milk")
            if self.headerValue(request, "If-None-Match") == "\"v\(version)\"" {
                return .init(status: 304, headers: ["ETag": "\"v\(version)\""])
            }
            return .init(status: 200, headers: ["ETag": "\"v\(version)\""], body: Data(json.utf8))
        }
        let cache = AssetCache(root: root)
        let store = CardStore(api: makeAPI(), cache: cache, player: SpeechPlayer(), thumbnails: ThumbnailCache())
        await store.refresh()
        XCTAssertEqual(store.cards.map(\.slug), ["juice"])

        version = 2
        await store.refresh()
        XCTAssertEqual(store.cards.map(\.slug), ["milk"])
        XCTAssertEqual(cache.boardETag(folderId: nil), "\"v2\"")
    }

    func testEmptyScreenNeverSendsAValidator() async throws {
        let cache = AssetCache(root: root)
        cache.saveBoardETag("\"stale\"", folderId: nil)
        ConditionalURLProtocol.handler = { request in
            guard request.url?.path == "/v1/board" else { return .init(status: 304) }
            return .init(status: 200, headers: ["ETag": "\"v1\""], body: Data(Self.boardJSON.utf8))
        }
        let store = CardStore(api: makeAPI(), cache: cache, player: SpeechPlayer(), thumbnails: ThumbnailCache())
        await store.refresh()
        let first = ConditionalURLProtocol.requests.first { $0.url?.path == "/v1/board" }
        XCTAssertNil(first.flatMap { headerValue($0, "If-None-Match") }, "no cached board, so a 304 could not be honoured")
        XCTAssertEqual(store.cards.count, 1)
    }

    // MARK: Pictures and voices

    private func card() -> Card {
        Card(word: "juice", slug: "juice", imageURL: "/assets/juice/image.png", audioURL: "/assets/juice/audio.mp3")
    }

    private func seedFiles(_ cache: AssetCache) throws {
        try FileManager.default.createDirectory(at: cache.directory(for: "juice"), withIntermediateDirectories: true)
        try Data("old-image".utf8).write(to: cache.imageURL(for: "juice"))
        try Data("old-audio".utf8).write(to: cache.audioURL(for: "juice"))
    }

    func testFilesOnDiskAreNotRequestedAgainByDefault() async throws {
        let cache = AssetCache(root: root)
        try seedFiles(cache)
        ConditionalURLProtocol.handler = { _ in .init(status: 500) }
        let changed = await cache.ensureAssets(for: card(), api: makeAPI())
        XCTAssertFalse(changed)
        XCTAssertTrue(ConditionalURLProtocol.requests.isEmpty, "cached pictures and voices cost zero requests")
    }

    func testMissingFilesAreDownloadedAndTheirValidatorsKept() async throws {
        let cache = AssetCache(root: root)
        ConditionalURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("image.png") == true {
                return .init(status: 200, headers: ["ETag": "\"img1\""], body: Data("image-bytes".utf8))
            }
            return .init(status: 200, headers: ["ETag": "\"aud1\""], body: Data("audio-bytes".utf8))
        }
        let changed = await cache.ensureAssets(for: card(), api: makeAPI())
        XCTAssertTrue(changed)
        XCTAssertEqual(try String(contentsOf: cache.imageURL(for: "juice"), encoding: .utf8), "image-bytes")
        XCTAssertEqual(try String(contentsOf: cache.audioURL(for: "juice"), encoding: .utf8), "audio-bytes")
        let sidecar = cache.directory(for: "juice").appendingPathComponent("image.etag")
        XCTAssertEqual(try String(contentsOf: sidecar, encoding: .utf8), "\"img1\"")
    }

    func testRevalidationUsesIfNoneMatchAndKeepsFilesOn304() async throws {
        let cache = AssetCache(root: root)
        try seedFiles(cache)
        try Data("\"img1\"".utf8).write(to: cache.directory(for: "juice").appendingPathComponent("image.etag"))
        ConditionalURLProtocol.handler = { _ in .init(status: 304) }

        let changed = await cache.ensureAssets(for: card(), api: makeAPI(), revalidate: true)

        XCTAssertFalse(changed)
        XCTAssertEqual(try String(contentsOf: cache.imageURL(for: "juice"), encoding: .utf8), "old-image")
        let image = try XCTUnwrap(ConditionalURLProtocol.requests.first { $0.url?.path.hasSuffix("image.png") == true })
        XCTAssertEqual(headerValue(image, "If-None-Match"), "\"img1\"")
        let audio = try XCTUnwrap(ConditionalURLProtocol.requests.first { $0.url?.path.hasSuffix("audio.mp3") == true })
        XCTAssertNil(headerValue(audio, "If-None-Match"))
        XCTAssertNotNil(headerValue(audio, "If-Modified-Since"), "files saved before validators existed use their saved date")
    }

    func testRevalidationReplacesAPictureTheServerChanged() async throws {
        let cache = AssetCache(root: root)
        try seedFiles(cache)
        ConditionalURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("image.png") == true {
                return .init(status: 200, headers: ["ETag": "\"img2\""], body: Data("new-image".utf8))
            }
            return .init(status: 304)
        }
        let changed = await cache.ensureAssets(for: card(), api: makeAPI(), revalidate: true)
        XCTAssertTrue(changed)
        XCTAssertEqual(try String(contentsOf: cache.imageURL(for: "juice"), encoding: .utf8), "new-image")
        XCTAssertEqual(try String(contentsOf: cache.audioURL(for: "juice"), encoding: .utf8), "old-audio")
    }

    func testOnDevicePhotosAreNeverReplacedByTheServer() async throws {
        let cache = AssetCache(root: root)
        try seedFiles(cache)
        try Data("local".utf8).write(to: cache.localImageMarkerURL(for: "juice"))
        ConditionalURLProtocol.handler = { _ in .init(status: 200, body: Data("server".utf8)) }
        _ = await cache.ensureAssets(for: card(), api: makeAPI(), revalidate: true)
        XCTAssertEqual(try String(contentsOf: cache.imageURL(for: "juice"), encoding: .utf8), "old-image")
    }

    func testFailedRevalidationKeepsTheWarmFiles() async throws {
        let cache = AssetCache(root: root)
        try seedFiles(cache)
        ConditionalURLProtocol.handler = { _ in .init(status: 503) }
        let changed = await cache.ensureAssets(for: card(), api: makeAPI(), revalidate: true)
        XCTAssertFalse(changed)
        XCTAssertEqual(try String(contentsOf: cache.imageURL(for: "juice"), encoding: .utf8), "old-image")
        XCTAssertEqual(try String(contentsOf: cache.audioURL(for: "juice"), encoding: .utf8), "old-audio")
    }
}
