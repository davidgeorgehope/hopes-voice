import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Decoded, trimmed, downsampled card pictures.
///
/// The board used to read a full-size PNG from disk, decode it, scan every pixel to trim the
/// white margin, and re-render it on the main thread each time SwiftUI rebuilt a cell. That is
/// seconds of main-thread work on a 500-card board. Now:
///
/// - `thumbnail(for:)` is a memory-only lookup. It never touches the disk or decodes anything
///   on the caller's thread. On a miss it returns `nil` and loads in the background.
/// - A background load first looks for a small JPEG thumbnail next to the picture (the
///   persistent disk cache). If there is none, it decodes the original once, trims the white
///   margin with the same rule as `PecsImage`, scales to `side` pixels, and writes that JPEG.
/// - The decoded bitmap is kept in an `NSCache`, so later lookups are free.
///
/// Entries are keyed by path, modification time, and size, so replacing a picture invalidates it
/// without any explicit bookkeeping.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    /// Longest side of a stored thumbnail, in pixels. About 3× a phone cell, 2× an iPad cell.
    static let side = 320
    static let thumbnailFileName = "thumb-v1.jpg"
    /// Originals larger than this are decoded at reduced size first (photos from the library).
    private static let maxDecodeSide = 1536

    private let memory = NSCache<NSString, UIImage>()
    private let queue: OperationQueue
    private let lock = NSLock()
    private var inflight: [String: [@Sendable () -> Void]] = [:]
    private let counters = Counters()

    /// Number of background builds that had to decode an original (tests read this).
    var decodedOriginalCount: Int { counters.decodedOriginals }
    /// Number of background loads served from the on-disk thumbnail.
    var diskHitCount: Int { counters.diskHits }

    init(memoryLimitBytes: Int = 96 * 1024 * 1024, concurrency: Int = 3) {
        memory.totalCostLimit = memoryLimitBytes
        queue = OperationQueue()
        queue.name = "com.davidgeorgehope.hopesvoice.thumbnails"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = concurrency
    }

    // MARK: - Lookup

    /// Decoded thumbnail if it is already in memory. Otherwise `nil`, and a background load is
    /// started; `onLoaded` runs on the main queue once it lands.
    func thumbnail(for source: URL, onLoaded: @escaping @Sendable () -> Void = {}) -> UIImage? {
        guard let key = Self.key(for: source) else { return nil }
        if let hit = memory.object(forKey: key as NSString) { return hit }
        schedule(source: source, key: key, onLoaded: onLoaded)
        return nil
    }

    /// In memory right now, without scheduling anything.
    func cachedThumbnail(for source: URL) -> UIImage? {
        guard let key = Self.key(for: source) else { return nil }
        return memory.object(forKey: key as NSString)
    }

    /// Warm the cache for pictures that are about to be shown.
    func prefetch(_ sources: [URL]) {
        for source in sources {
            guard let key = Self.key(for: source), memory.object(forKey: key as NSString) == nil else { continue }
            schedule(source: source, key: key, onLoaded: {})
        }
    }

    /// Blocking variant for tests and tools. Never call from the UI.
    func loadSynchronously(_ source: URL) -> UIImage? {
        guard let key = Self.key(for: source) else { return nil }
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let image = build(source: source)
        if let image { store(image, key: key) }
        return image
    }

    func removeAll() {
        memory.removeAllObjects()
    }

    // MARK: - Loading

    private func schedule(source: URL, key: String, onLoaded: @escaping @Sendable () -> Void) {
        lock.lock()
        if inflight[key] != nil {
            inflight[key]?.append(onLoaded)
            lock.unlock()
            return
        }
        inflight[key] = [onLoaded]
        lock.unlock()

        queue.addOperation { [weak self] in
            guard let self else { return }
            let image = self.build(source: source)
            if let image { self.store(image, key: key) }
            self.lock.lock()
            let callbacks = self.inflight.removeValue(forKey: key) ?? []
            self.lock.unlock()
            guard image != nil else { return }
            DispatchQueue.main.async { callbacks.forEach { $0() } }
        }
    }

    private func store(_ image: UIImage, key: String) {
        let cost = max(Int(image.size.width * image.scale * image.size.height * image.scale) * 4, 1)
        memory.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Disk thumbnail if it is at least as new as the picture, else build from the original.
    private func build(source: URL) -> UIImage? {
        let thumbURL = source.deletingLastPathComponent().appendingPathComponent(Self.thumbnailFileName)
        if Self.isFresh(thumb: thumbURL, source: source), let image = Self.decode(url: thumbURL) {
            counters.addDiskHit()
            return image
        }
        counters.addDecodedOriginal()
        guard let image = Self.makeThumbnail(from: source, side: Self.side) else { return nil }
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: thumbURL, options: .atomic)
        }
        return image
    }

    private final class Counters: @unchecked Sendable {
        private let lock = NSLock()
        private var _decoded = 0
        private var _disk = 0
        var decodedOriginals: Int { lock.lock(); defer { lock.unlock() }; return _decoded }
        var diskHits: Int { lock.lock(); defer { lock.unlock() }; return _disk }
        func addDecodedOriginal() { lock.lock(); _decoded += 1; lock.unlock() }
        func addDiskHit() { lock.lock(); _disk += 1; lock.unlock() }
    }

    // MARK: - Keys and files

    /// `path|mtime|size`, from one `stat`. `nil` when the picture does not exist.
    static func key(for url: URL) -> String? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return "\(url.path)|\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)|\(info.st_size)"
    }

    private static func isFresh(thumb: URL, source: URL) -> Bool {
        var t = stat()
        var s = stat()
        guard stat(thumb.path, &t) == 0, stat(source.path, &s) == 0 else { return false }
        if t.st_mtimespec.tv_sec != s.st_mtimespec.tv_sec { return t.st_mtimespec.tv_sec > s.st_mtimespec.tv_sec }
        return t.st_mtimespec.tv_nsec >= s.st_mtimespec.tv_nsec
    }

    /// Fully decoded (not lazily) so the first draw on the main thread costs nothing.
    static func decode(url: URL) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else { return nil }
        let decodeOptions: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    // MARK: - Thumbnail construction (background threads only)

    /// Decode the original, crop near-white margins (same rule as `PecsImage.fillingSubject`),
    /// and fit the subject into a white square no larger than `side` pixels.
    static func makeThumbnail(from url: URL, side: Int) -> UIImage? {
        guard let cgImage = decodeForTrimming(url: url) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        guard let bounds = contentBounds(of: cgImage) else {
            // Blank picture: nothing to trim, just scale it down.
            return render(cgImage, crop: CGRect(x: 0, y: 0, width: width, height: height), side: side)
        }
        return render(cgImage, crop: bounds, side: side)
    }

    private static func decodeForTrimming(url: URL) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        if max(pixelWidth, pixelHeight) > maxDecodeSide {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDecodeSide,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    /// Bounding box of pixels that are not transparent or near-white. `nil` if there are none.
    private static func contentBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var data = [UInt32](repeating: 0, count: width * height)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let threshold = UInt32(PecsImage.whiteThreshold)
        var minX = width, minY = height, maxX = -1, maxY = -1
        data.withUnsafeBufferPointer { pixels in
            for y in 0..<height {
                let row = y * width
                var rowMin = -1
                var rowMax = -1
                for x in 0..<width {
                    // Memory order is R, G, B, A, so a little-endian UInt32 holds A in the top byte.
                    let p = pixels[row + x]
                    let r = p & 0xFF
                    let g = (p >> 8) & 0xFF
                    let b = (p >> 16) & 0xFF
                    let a = p >> 24
                    let isBackground = a < 8 || (r >= threshold && g >= threshold && b >= threshold)
                    if !isBackground {
                        if rowMin < 0 { rowMin = x }
                        rowMax = x
                    }
                }
                if rowMin >= 0 {
                    if rowMin < minX { minX = rowMin }
                    if rowMax > maxX { maxX = rowMax }
                    if y < minY { minY = y }
                    maxY = y
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Crop to `crop`, then draw it centred on an opaque white square with a `marginFraction` border.
    private static func render(_ image: CGImage, crop: CGRect, side: Int) -> UIImage? {
        guard let cropped = image.cropping(to: crop) else { return nil }
        let content = max(crop.width, crop.height)
        let fill = max(1 - 2 * PecsImage.marginFraction, 0.5)
        // Never scale up: a small subject keeps its pixels and the view scales the canvas.
        let scale = min(CGFloat(side) * fill / content, 1)
        let canvas = max(Int((content * scale / fill).rounded()), Int((content * scale).rounded()) + 2)
        let drawW = max((crop.width * scale).rounded(), 1)
        let drawH = max((crop.height * scale).rounded(), 1)

        guard let context = CGContext(
            data: nil,
            width: canvas,
            height: canvas,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(
            x: (CGFloat(canvas) - drawW) / 2,
            y: (CGFloat(canvas) - drawH) / 2,
            width: drawW,
            height: drawH
        ))
        guard let out = context.makeImage() else { return nil }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }
}
