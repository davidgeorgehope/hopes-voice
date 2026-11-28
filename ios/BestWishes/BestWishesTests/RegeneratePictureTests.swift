import UIKit
import XCTest
@testable import BestWishes

/// "New picture" on an existing word asks the server for a new picture and the board shows it,
/// even when this device had a caregiver photo or an older cached copy for that word.
@MainActor
final class RegeneratePictureTests: XCTestCase {
    private var session: URLSession!
    private var root: URL!

    override func setUpWithError() throws {
        ConditionalURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConditionalURLProtocol.self]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 4
        session = URLSession(configuration: config)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-regen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        ConditionalURLProtocol.reset()
        try? FileManager.default.removeItem(at: root)
    }

    private func solidPNG(_ color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    func testNewPictureReplacesTheOldOneOnDisk() async throws {
        let newPicture = solidPNG(.blue)
        ConditionalURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST", path == "/v1/cards/juice/image" {
                let body = #"{"word":"juice","slug":"juice","image_url":"/assets/juice/image.png","audio_url":"/assets/juice/audio.mp3"}"#
                return .init(status: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
            }
            if path == "/assets/juice/image.png" {
                return .init(status: 200, headers: ["ETag": "\"v2\""], body: newPicture)
            }
            if path == "/assets/juice/audio.mp3" {
                return .init(status: 200, headers: ["ETag": "\"a1\""], body: Data("mp3".utf8))
            }
            return .init(status: 404)
        }
        let cache = AssetCache(root: root)
        XCTAssertTrue(cache.saveLocalImage(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }, for: "juice"))
        XCTAssertTrue(cache.isLocalImage("juice"))

        let store = CardStore(api: APIClient(baseURL: URL(string: "https://hopes.test")!, session: session),
                              cache: cache, player: SpeechPlayer())
        let ok = await store.regeneratePicture(for: "juice")

        XCTAssertTrue(ok)
        XCTAssertTrue(ConditionalURLProtocol.requests.contains { $0.httpMethod == "POST" && $0.url?.path == "/v1/cards/juice/image" })
        XCTAssertFalse(cache.isLocalImage("juice"), "the server picture replaces the on-device photo")
        XCTAssertEqual(try Data(contentsOf: cache.imageURL(for: "juice")), newPicture)
        XCTAssertNil(store.errorMessage)
    }

    func testServerRefusalKeepsTheOldPicture() async throws {
        ConditionalURLProtocol.handler = { _ in .init(status: 429, body: Data(#"{"detail":"Wait a moment"}"#.utf8)) }
        let cache = AssetCache(root: root)
        XCTAssertTrue(cache.saveLocalImage(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }, for: "juice"))
        let before = try Data(contentsOf: cache.imageURL(for: "juice"))

        let store = CardStore(api: APIClient(baseURL: URL(string: "https://hopes.test")!, session: session),
                              cache: cache, player: SpeechPlayer())
        let ok = await store.regeneratePicture(for: "juice")

        XCTAssertFalse(ok)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(cache.isLocalImage("juice"))
        XCTAssertEqual(try Data(contentsOf: cache.imageURL(for: "juice")), before)
    }
}
