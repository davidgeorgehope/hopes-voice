import UIKit
import XCTest
@testable import BestWishes

/// In-memory stand-in for the `/v1/sync` API. Enough to prove the protocol: ETags, If-Match, blobs.
nonisolated final class FakeSyncServer: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var versions: [String: [SyncRecord]] = [:]
    nonisolated(unsafe) private static var blobs: [String: Data] = [:]
    nonisolated(unsafe) static var reachable = true
    nonisolated(unsafe) static var counts: [String: Int] = [:]

    static func reset() {
        lock.withLock {
            versions = [:]; blobs = [:]; reachable = true; counts = [:]
        }
    }

    static func count(_ key: String) -> Int { lock.withLock { counts[key] ?? 0 } }
    static func head(_ id: String) -> SyncRecord? { lock.withLock { versions[id]?.last } }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeSyncServer.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    private func reply(_ status: Int, _ body: Data = Data(), headers: [String: String] = [:]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func startLoading() {
        guard Self.lock.withLock({ Self.reachable }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" else { return reply(401) }
        let method = request.httpMethod ?? "GET"
        let path = request.url!.path
        let body = request.httpBody ?? request.httpBodyStream.flatMap { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            return data
        } ?? Data()
        let encoder = JSONEncoder()

        Self.lock.withLock {
            let key = "\(method) " + (path.contains("/blobs/") ? "blob" : path)
            Self.counts[key, default: 0] += 1
        }

        if path == "/v1/sync/profiles", method == "GET" {
            let items = Self.lock.withLock { Self.versions.values.compactMap(\.last) }.map { r -> SyncRecord in
                var s = r; s.doc = nil; return s
            }
            let tag = "\"m-\(items.map { "\($0.profile_id)\($0.version)" }.sorted().joined())\""
            if request.value(forHTTPHeaderField: "If-None-Match") == tag { return reply(304, headers: ["ETag": tag]) }
            return reply(200, try! encoder.encode(SyncManifest(profiles: items)), headers: ["ETag": tag])
        }
        let parts = path.split(separator: "/").map(String.init)
        if parts.count == 4, parts[2] == "profiles" {
            let id = parts[3]
            let head = Self.lock.withLock { Self.versions[id]?.last }
            if method == "GET" {
                guard let head else { return reply(404, Data(#"{"detail":"profile has no synced board yet"}"#.utf8)) }
                if request.value(forHTTPHeaderField: "If-None-Match") == "\"\(head.version)\"" { return reply(304) }
                return reply(200, try! encoder.encode(head), headers: ["ETag": "\"\(head.version)\""])
            }
            if method == "PUT" {
                struct Body: Decodable { var doc: SyncDoc; var note: String }
                let expected = request.value(forHTTPHeaderField: "If-Match")
                let current = head?.version ?? 0
                guard expected == "\"\(current)\"" else {
                    return reply(412, Data(#"{"detail":"version conflict","current_version":\#(current)}"#.utf8))
                }
                let parsed = try! JSONDecoder().decode(Body.self, from: body)
                if let head, head.doc == parsed.doc { return reply(200, try! encoder.encode(head)) }
                let record = SyncRecord(profile_id: id, version: current + 1, updated_at: "now", author: "test", note: parsed.note, doc: parsed.doc)
                Self.lock.withLock { Self.versions[id, default: []].append(record) }
                return reply(200, try! encoder.encode(record))
            }
        }
        if path.hasPrefix("/v1/sync/blobs/") {
            let sha = parts.last!
            switch method {
            case "HEAD": return reply(Self.lock.withLock { Self.blobs[sha] } != nil ? 200 : 404)
            case "PUT": Self.lock.withLock { Self.blobs[sha] = body }; return reply(200, Data("{}".utf8))
            case "GET":
                if let data = Self.lock.withLock({ Self.blobs[sha] }) { return reply(200, data) }
                return reply(404)
            default: break
            }
        }
        reply(404)
    }
}

final class SyncEngineTests: XCTestCase {
    private let base = URL(string: "https://sync.invalid")!

    override func setUp() { FakeSyncServer.reset() }

    private func device() throws -> (AssetCache, SyncWorker, SyncClient) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-sync-\(UUID().uuidString)", isDirectory: true)
        let cache = AssetCache(root: root)
        let client = SyncClient(baseURL: base, token: "test-token", session: FakeSyncServer.session())
        return (cache, SyncWorker(cache: cache, deviceName: "test"), client)
    }

    private func png(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func applyStaged(_ cache: AssetCache, profile: KidProfile = .child1) {
        guard let plan = SyncPlanner.makeApplyPlan(cache, profile) else { return }
        SyncPlanner.writeOverlays(plan.final.overlays, cache: cache, profile: profile)
        SyncPlanner.commitApply(cache, profile)
    }

    func testEditOnOneDeviceAppearsOnTheOther() async throws {
        let (cacheA, workerA, client) = try device()
        let (cacheB, workerB, _) = try device()
        cacheA.saveLabelOverlays(["more": "Again"], for: .child1)
        cacheA.saveHiddenSlugs(["stop"], for: .child1)

        let pushed = try await workerA.sync(profile: .child1, profileID: "child1", client: client)
        XCTAssertTrue(pushed.pushed)
        XCTAssertEqual(pushed.version, 1)

        let pulled = try await workerB.sync(profile: .child1, profileID: "child1", client: client)
        XCTAssertTrue(pulled.hasPendingUpdate, "the update is staged, not applied under the user's hands")
        XCTAssertEqual(cacheB.loadLabelOverlays(for: .child1), [:], "nothing changes until the app applies it")

        applyStaged(cacheB)
        XCTAssertEqual(cacheB.loadLabelOverlays(for: .child1), ["more": "Again"])
        XCTAssertEqual(cacheB.loadHiddenSlugs(for: .child1), ["stop"])
        XCTAssertNil(SyncPlanner.loadState(cacheB, .child1).pending)
    }

    func testUnchangedBoardIsA304AndPushesNothing() async throws {
        let (cache, worker, client) = try device()
        cache.saveLabelOverlays(["a": "A"], for: .child1)
        _ = try await worker.sync(profile: .child1, profileID: "child1", client: client)
        let puts = FakeSyncServer.count("PUT /v1/sync/profiles/child1")
        let again = try await worker.sync(profile: .child1, profileID: "child1", client: client)
        XCTAssertFalse(again.pushed)
        XCTAssertFalse(again.hasPendingUpdate)
        XCTAssertEqual(FakeSyncServer.count("PUT /v1/sync/profiles/child1"), puts)
        let manifest = try await client.manifest(etag: nil)
        let second = try await client.manifest(etag: manifest?.etag)
        XCTAssertNil(second, "manifest answers 304 when no profile changed")
    }

    func testConcurrentEditsOnTwoDevicesMergeInsteadOfOverwriting() async throws {
        let (cacheA, workerA, client) = try device()
        let (cacheB, workerB, _) = try device()
        cacheA.saveLabelOverlays(["a": "start"], for: .child1)
        _ = try await workerA.sync(profile: .child1, profileID: "child1", client: client)
        _ = try await workerB.sync(profile: .child1, profileID: "child1", client: client)
        applyStaged(cacheB)

        cacheA.saveLabelOverlays(["a": "start", "b": "from A"], for: .child1)
        cacheB.saveLabelOverlays(["a": "start", "c": "from B"], for: .child1)
        _ = try await workerA.sync(profile: .child1, profileID: "child1", client: client)
        let b = try await workerB.sync(profile: .child1, profileID: "child1", client: client)
        XCTAssertTrue(b.pushed)
        XCTAssertEqual(FakeSyncServer.head("child1")?.doc?.overlays.labels, ["a": "start", "b": "from A", "c": "from B"])
        applyStaged(cacheB)
        XCTAssertEqual(cacheB.loadLabelOverlays(for: .child1)["b"], "from A")
        XCTAssertEqual(cacheB.loadLabelOverlays(for: .child1)["c"], "from B")
    }

    func testEditsMadeWhileAnUpdateWaitsAreNotLostWhenItApplies() async throws {
        let (cacheA, workerA, client) = try device()
        let (cacheB, workerB, _) = try device()
        cacheA.saveLabelOverlays(["a": "from A"], for: .child1)
        _ = try await workerA.sync(profile: .child1, profileID: "child1", client: client)
        _ = try await workerB.sync(profile: .child1, profileID: "child1", client: client)   // staged on B
        cacheB.saveLabelOverlays(["z": "typed on B meanwhile"], for: .child1)
        applyStaged(cacheB)
        XCTAssertEqual(cacheB.loadLabelOverlays(for: .child1), ["a": "from A", "z": "typed on B meanwhile"])
        let push = try await workerB.sync(profile: .child1, profileID: "child1", client: client)
        XCTAssertTrue(push.pushed, "the meanwhile edit still goes up")
        XCTAssertEqual(FakeSyncServer.head("child1")?.doc?.overlays.labels["z"], "typed on B meanwhile")
    }

    func testOfflineKeepsLocalBoardAndRetriesLater() async throws {
        let (cache, worker, client) = try device()
        cache.saveLabelOverlays(["a": "kept"], for: .child1)
        FakeSyncServer.reachable = false
        do {
            _ = try await worker.sync(profile: .child1, profileID: "child1", client: client)
            XCTFail("offline must throw, not hang or wipe")
        } catch let error as SyncError {
            guard case .offline = error else { return XCTFail("expected offline, got \(error)") }
        }
        XCTAssertEqual(cache.loadLabelOverlays(for: .child1), ["a": "kept"])
        FakeSyncServer.reachable = true
        let outcome = try await worker.sync(profile: .child1, profileID: "child1", client: client)
        XCTAssertTrue(outcome.pushed)
        XCTAssertEqual(FakeSyncServer.head("child1")?.doc?.overlays.labels, ["a": "kept"])
    }

    func testWrongTokenIsReportedAndNothingIsApplied() async throws {
        let (cache, worker, _) = try device()
        let bad = SyncClient(baseURL: base, token: "nope", session: FakeSyncServer.session())
        cache.saveLabelOverlays(["a": "mine"], for: .child1)
        do {
            _ = try await worker.sync(profile: .child1, profileID: "child1", client: bad)
            XCTFail("expected unauthorized")
        } catch let error as SyncError {
            guard case .unauthorized = error else { return XCTFail("got \(error)") }
        }
        XCTAssertEqual(cache.loadLabelOverlays(for: .child1), ["a": "mine"])
    }

    func testCaregiverPhotoTravelsOnceByContentHash() async throws {
        let (cacheA, workerA, client) = try device()
        let (cacheB, workerB, _) = try device()
        XCTAssertTrue(cacheA.saveLocalImage(png(.systemTeal), for: "more"))
        _ = try await workerA.sync(profile: .child1, profileID: "child1", client: client)
        XCTAssertEqual(FakeSyncServer.count("PUT blob"), 1)
        _ = try await workerA.sync(profile: .child1, profileID: "child1", client: client)
        XCTAssertEqual(FakeSyncServer.count("PUT blob"), 1, "an unchanged picture is never uploaded twice")

        _ = try await workerB.sync(profile: .child1, profileID: "child1", client: client)
        applyStaged(cacheB)
        // pictures are copied while planning the apply
        XCTAssertTrue(cacheB.hasImage("more"))
        XCTAssertTrue(cacheB.isLocalImage("more"))
        XCTAssertEqual(try Data(contentsOf: cacheB.imageURL(for: "more")), try Data(contentsOf: cacheA.imageURL(for: "more")))
        let again = try await workerB.sync(profile: .child1, profileID: "child1", client: client)
        XCTAssertFalse(again.pushed, "applying a picture is not a local edit")
    }

    func testApplyingDoesNotNotifyTheChangeObserver() async throws {
        let (cacheA, workerA, client) = try device()
        let (cacheB, workerB, _) = try device()
        cacheA.saveLabelOverlays(["a": "x"], for: .child1)
        _ = try await workerA.sync(profile: .child1, profileID: "child1", client: client)
        _ = try await workerB.sync(profile: .child1, profileID: "child1", client: client)
        let noted = NSLock()
        nonisolated(unsafe) var calls = 0
        cacheB.setChangeObserver { _ in noted.withLock { calls += 1 } }
        applyStaged(cacheB)
        XCTAssertEqual(noted.withLock { calls }, 0)
        cacheB.saveLabelOverlays(["a": "y"], for: .child1)
        XCTAssertEqual(noted.withLock { calls }, 1, "a real edit does notify")
    }

    func testProfilesSyncIndependently() async throws {
        let (cacheA, workerA, client) = try device()
        cacheA.saveLabelOverlays(["a": "one"], for: .child1)
        cacheA.saveLabelOverlays(["a": "two"], for: .child2)
        _ = try await workerA.sync(profile: .child1, profileID: "child1", client: client)
        _ = try await workerA.sync(profile: .child2, profileID: "child2", client: client)
        XCTAssertEqual(FakeSyncServer.head("child1")?.doc?.overlays.labels["a"], "one")
        XCTAssertEqual(FakeSyncServer.head("child2")?.doc?.overlays.labels["a"], "two")
    }
}
