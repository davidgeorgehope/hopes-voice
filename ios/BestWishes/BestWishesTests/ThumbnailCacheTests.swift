import XCTest
import UIKit
@testable import BestWishes

/// Issue #27: pictures are decoded, trimmed and downsampled once, off the main thread,
/// and then served from memory (and from a small thumbnail on disk after a relaunch).
final class ThumbnailCacheTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-thumb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// White square with a coloured block of `block` pixels in the middle.
    private func writePicture(
        _ name: String = "image.png",
        side: Int = 1024,
        block: Int = 400,
        color: UIColor = .red
    ) throws -> URL {
        let dir = root.appendingPathComponent(name.replacingOccurrences(of: ".", with: "_"), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("image.png")
        try renderPNG(side: side, block: block, color: color).write(to: url)
        return url
    }

    private func renderPNG(side: Int, block: Int, color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            color.setFill()
            let origin = (side - block) / 2
            ctx.fill(CGRect(x: origin, y: origin, width: block, height: block))
        }
    }

    private func centrePixel(_ image: UIImage) -> (r: Int, g: Int, b: Int) {
        guard let cg = image.cgImage else { return (0, 0, 0) }
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(cg, in: CGRect(x: -cg.width / 2, y: -cg.height / 2, width: cg.width, height: cg.height))
        }
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    func testThumbnailIsTrimmedAndDownsampled() throws {
        let url = try writePicture(side: 1024, block: 300)
        let image = try XCTUnwrap(ThumbnailCache(memoryLimitBytes: 1 << 26).loadSynchronously(url))

        XCTAssertLessThanOrEqual(Int(image.size.width), ThumbnailCache.side)
        XCTAssertLessThanOrEqual(Int(image.size.height), ThumbnailCache.side)
        let box = try XCTUnwrap(PecsImage.contentPixelBBox(image))
        let fill = max(box.width, box.height) / max(image.size.width, image.size.height)
        XCTAssertGreaterThan(fill, 0.80, "subject should fill the thumbnail, not sit in a big white square")
        XCTAssertLessThan(fill, 0.95, "a small margin is kept around the subject")
    }

    func testSmallPicturesAreNotUpscaled() throws {
        let url = try writePicture(side: 64, block: 40)
        let image = try XCTUnwrap(ThumbnailCache().loadSynchronously(url))
        XCTAssertLessThanOrEqual(Int(image.size.width), 64)
    }

    func testMissingFileGivesNilAndSchedulesNothing() {
        let cache = ThumbnailCache()
        let missing = root.appendingPathComponent("nope/image.png")
        XCTAssertNil(cache.thumbnail(for: missing))
        XCTAssertNil(cache.loadSynchronously(missing))
        XCTAssertEqual(cache.decodedOriginalCount, 0)
    }

    func testLookupDoesNotBlockAndDeliversThePictureLater() throws {
        let url = try writePicture()
        let cache = ThumbnailCache()
        let loaded = expectation(description: "picture loaded in the background")
        XCTAssertNil(cache.thumbnail(for: url) { loaded.fulfill() }, "first lookup must not decode on the caller's thread")
        wait(for: [loaded], timeout: 10)
        let first = try XCTUnwrap(cache.thumbnail(for: url))
        let second = try XCTUnwrap(cache.thumbnail(for: url))
        XCTAssertTrue(first === second, "later lookups are the same decoded bitmap from memory")
        XCTAssertEqual(cache.decodedOriginalCount, 1)
    }

    func testConcurrentLookupsOfOnePictureDecodeItOnce() throws {
        let url = try writePicture()
        let cache = ThumbnailCache()
        let loaded = expectation(description: "all callbacks ran")
        loaded.expectedFulfillmentCount = 5
        for _ in 0..<5 { _ = cache.thumbnail(for: url) { loaded.fulfill() } }
        wait(for: [loaded], timeout: 10)
        XCTAssertEqual(cache.decodedOriginalCount, 1)
    }

    func testDiskThumbnailIsWrittenAndReusedAfterRelaunch() throws {
        let url = try writePicture()
        let first = ThumbnailCache()
        XCTAssertNotNil(first.loadSynchronously(url))
        let thumb = url.deletingLastPathComponent().appendingPathComponent(ThumbnailCache.thumbnailFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumb.path), "thumbnail should be persisted next to the picture")
        let thumbBytes = try Data(contentsOf: thumb).count
        let originalBytes = try Data(contentsOf: url).count
        XCTAssertLessThan(thumbBytes, originalBytes, "the disk thumbnail is smaller than the original")

        let relaunched = ThumbnailCache()
        XCTAssertNotNil(relaunched.loadSynchronously(url))
        XCTAssertEqual(relaunched.decodedOriginalCount, 0, "a relaunch must not decode the original again")
        XCTAssertEqual(relaunched.diskHitCount, 1)
    }

    func testReplacingThePictureInvalidatesTheThumbnail() throws {
        let url = try writePicture(color: .red)
        let cache = ThumbnailCache()
        let before = centrePixel(try XCTUnwrap(cache.loadSynchronously(url)))
        XCTAssertGreaterThan(before.r, 200)
        XCTAssertLessThan(before.b, 80)

        try renderPNG(side: 1024, block: 400, color: .blue).write(to: url)
        // Make sure the file's modification time moves even on a coarse clock.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)

        let after = centrePixel(try XCTUnwrap(cache.loadSynchronously(url)))
        XCTAssertGreaterThan(after.b, 200, "the new picture must be shown, not the cached old one")
        XCTAssertLessThan(after.r, 80)
    }

    func testMemoryLimitEvictsInsteadOfGrowingForever() throws {
        let cache = ThumbnailCache(memoryLimitBytes: 3 * 320 * 320 * 4)
        var urls: [URL] = []
        for i in 0..<12 { urls.append(try writePicture("p\(i).png")) }
        for url in urls { XCTAssertNotNil(cache.loadSynchronously(url)) }
        let resident = urls.filter { cache.cachedThumbnail(for: $0) != nil }.count
        XCTAssertLessThan(resident, 12, "NSCache should have evicted some entries")
    }
}
