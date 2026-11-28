import XCTest
import SwiftUI
import UIKit
import QuartzCore
@testable import BestWishes

/// Issue #27 performance checks on a large synthetic board (500 cards, each with a 1024×1024
/// picture on disk). The numbers are main-thread busy time, measured the way a child feels it:
/// from the tap (or from creating the screen) until the main thread has nothing left to do.
@MainActor
final class PerformanceTests: XCTestCase {
    static let cardCount = 500
    /// Target from the issue: tap to visible feedback in under 100 ms.
    static let tapBudget: TimeInterval = 0.100
    /// Loose ceilings for the other checks. They are set about 10x above what a Debug build on a
    /// CI simulator measures after the fix, and 4-40x below the old code, so only a real
    /// regression (decoding on the main thread again) trips them.
    static let coldRenderBudget: TimeInterval = 0.600
    static let lookupBudget: TimeInterval = 0.150
    static let warmPicturesBudget: TimeInterval = 0.600

    private var roots: [URL] = []

    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
        super.tearDown()
    }

    // MARK: - Synthetic board

    /// A 1024² picture shaped like the AI cards: a coloured subject in the middle of white.
    private static func samplePNG() -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format)
        return renderer.pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            let colors: [UIColor] = [.systemOrange, .systemTeal, .systemPink, .systemIndigo]
            for i in 0..<24 {
                colors[i % colors.count].withAlphaComponent(0.85).setFill()
                let inset = CGFloat(300 + (i % 6) * 12)
                ctx.cgContext.fillEllipse(in: CGRect(x: inset, y: inset + CGFloat(i * 3), width: 1024 - 2 * inset, height: 1024 - 2 * inset))
            }
        }
    }

    /// 0.1 s of silence as a WAV; AVAudioPlayer sniffs the content, so the .mp3 name is fine.
    private static func sampleAudio() -> Data {
        let sampleRate = 8000
        let samples = sampleRate / 10
        var data = Data()
        func le32(_ v: Int) { var x = UInt32(v).littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func le16(_ v: Int) { var x = UInt16(v).littleEndian; data.append(Data(bytes: &x, count: 2)) }
        data.append("RIFF".data(using: .ascii)!); le32(36 + samples * 2)
        data.append("WAVEfmt ".data(using: .ascii)!); le32(16); le16(1); le16(1)
        le32(sampleRate); le32(sampleRate * 2); le16(2); le16(16)
        data.append("data".data(using: .ascii)!); le32(samples * 2)
        data.append(Data(count: samples * 2))
        return data
    }

    private func makeBoard(
        count: Int = cardCount,
        thumbnails: ThumbnailCache = ThumbnailCache()
    ) throws -> (CardStore, AssetCache, [Card]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bw-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let cache = AssetCache(root: root)
        let png = Self.samplePNG()
        let audio = Self.sampleAudio()
        var cards: [Card] = []
        for i in 0..<count {
            let slug = "word-\(i)"
            let card = Card(
                word: "Word \(i)",
                slug: slug,
                imageURL: "/assets/\(slug)/image.png",
                audioURL: "/assets/\(slug)/audio.mp3"
            )
            cards.append(card)
            try FileManager.default.createDirectory(at: cache.directory(for: slug), withIntermediateDirectories: true)
            try png.write(to: cache.imageURL(for: slug))
            try audio.write(to: cache.audioURL(for: slug))
        }
        let api = APIClient(baseURL: APIClient.unreachableBaseURL)
        // The app warms the audio session at launch (CardStore.load); do the same, and let it finish.
        let player = SpeechPlayer()
        player.warmUp()
        Thread.sleep(forTimeInterval: 0.5)
        let store = CardStore(api: api, cache: cache, player: player, thumbnails: thumbnails)
        store.seedLocalBoard(cards: cards, folders: [])
        return (store, cache, cards)
    }

    private func makeWindow(store: CardStore) -> UIWindow {
        let suite = "bw-perf-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let grid = GridLayout(defaults: defaults)
        let view = ContentView(
            store: store,
            mode: CaregiverMode(defaults: defaults),
            profiles: ProfileStore(defaults: defaults),
            grid: grid
        )
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return window
    }

    // MARK: - Measuring

    /// Total main-thread work caused by `action`: its own synchronous time, plus every run-loop
    /// pass (SwiftUI updates, layout, callbacks) until the main thread has been idle for 60 ms.
    /// Counted with a run-loop observer, so short passes are not lost to timer granularity.
    /// This is the longest the screen can lag behind a tap.
    @discardableResult
    private func mainThreadBusyTime(_ action: () -> Void) -> TimeInterval {
        let meter = LoopMeter()
        // The start observer runs first and the end observer last in every pass, so the Core
        // Animation commit (where SwiftUI does its layout work) is inside the measured span.
        let begin = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.afterWaiting.rawValue, true, Int.min
        ) { _, _ in meter.passStart = CACurrentMediaTime() }
        let end = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, Int.max
        ) { _, _ in
            if let start = meter.passStart {
                meter.busy += CACurrentMediaTime() - start
                meter.passStart = nil
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), begin, .commonModes)
        CFRunLoopAddObserver(CFRunLoopGetMain(), end, .commonModes)
        defer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), begin, .commonModes)
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), end, .commonModes)
        }

        let start = CACurrentMediaTime()
        action()
        let actionTime = CACurrentMediaTime() - start
        var quietSlices = 0
        let deadline = start + 30
        while quietSlices < 3, CACurrentMediaTime() < deadline {
            let before = meter.busy
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            quietSlices = (meter.busy - before) < 0.002 ? quietSlices + 1 : 0
        }
        return actionTime + meter.busy
    }

    private final class LoopMeter {
        var busy: TimeInterval = 0
        var passStart: TimeInterval?
    }

    private func report(_ name: String, _ values: [TimeInterval]) {
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let worst = sorted.last ?? 0
        let line = String(
            format: "PERF %@ median=%.1fms worst=%.1fms runs=%d",
            name, median * 1000, worst * 1000, values.count
        )
        print(line)
        if let path = ProcessInfo.processInfo.environment["HV_PERF_OUT"] ?? Optional("/tmp/hv-perf-results.txt"),
           let data = (line + "\n").data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
        let attachment = XCTAttachment(string: line)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func median(_ values: [TimeInterval]) -> TimeInterval {
        values.sorted()[values.count / 2]
    }

    // MARK: - Tests

    /// How long it takes to put the 500-card board on screen from cold.
    func testColdBoardRender() throws {
        var samples: [TimeInterval] = []
        for _ in 0..<3 {
            let (store, _, _) = try makeBoard()
            var window: UIWindow?
            samples.append(mainThreadBusyTime { window = makeWindow(store: store) })
            window?.isHidden = true
        }
        report("coldBoardRender500", samples)
        XCTAssertLessThan(median(samples), Self.coldRenderBudget, "median \(median(samples) * 1000) ms: 500-card board must reach the screen without decoding pictures on the main thread")
    }

    /// How long until the first screenful of pictures is actually drawn from a cold start
    /// (originals must be decoded) and from a relaunch (small thumbnails already on disk).
    func testFirstScreenOfPicturesAppear() throws {
        let visible = 12
        let (store, cache, cards) = try makeBoard(thumbnails: ThumbnailCache())
        func waitForPictures(_ thumbs: ThumbnailCache) -> TimeInterval {
            let start = CACurrentMediaTime()
            let window = makeWindow(store: store)
            defer { window.isHidden = true }
            let slugs = cards.map(\.slug)
            let deadline = start + 20
            while CACurrentMediaTime() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
                let ready = slugs.prefix(visible + 6).filter { thumbs.cachedThumbnail(for: cache.imageURL(for: $0)) != nil }.count
                if ready >= visible { break }
            }
            return CACurrentMediaTime() - start
        }
        let cold = waitForPictures(store.thumbnails)
        report("firstScreenPicturesColdDisk500", [cold])
        // Relaunch: new in-memory cache, thumbnails already written next to the pictures.
        let relaunched = ThumbnailCache()
        let (store2, _, _) = (CardStore(api: APIClient(baseURL: APIClient.unreachableBaseURL), cache: cache, player: SpeechPlayer(), thumbnails: relaunched), cache, cards)
        store2.seedLocalBoard(cards: cards, folders: [])
        let start = CACurrentMediaTime()
        let window2 = UIWindow(frame: UIScreen.main.bounds)
        window2.rootViewController = UIHostingController(rootView: ContentView(store: store2))
        window2.makeKeyAndVisible()
        defer { window2.isHidden = true }
        let deadline = start + 20
        while CACurrentMediaTime() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            let ready = cards.prefix(visible + 6).filter { relaunched.cachedThumbnail(for: cache.imageURL(for: $0.slug)) != nil }.count
            if ready >= visible { break }
        }
        let warm = CACurrentMediaTime() - start
        report("firstScreenPicturesWarmDisk500", [warm])
        XCTAssertLessThan(warm, Self.warmPicturesBudget, "after a relaunch the first screen of pictures comes from disk thumbnails")
    }

    /// Tap a word on a settled board: time until the message bar has been redrawn.
    func testTapToFeedbackLatency() throws {
        let (store, _, cards) = try makeBoard()
        let window = makeWindow(store: store)
        defer { window.isHidden = true }
        mainThreadBusyTime {}
        // Warm: first tap pays one-off audio session setup, so drop it from the numbers.
        mainThreadBusyTime { store.tap(cards[0]) }
        var samples: [TimeInterval] = []
        for i in 1...6 {
            samples.append(mainThreadBusyTime { store.tap(cards[i % 6]) })
            store.clearStrip()
            mainThreadBusyTime {}
        }
        report("tapToFeedback500", samples)
        XCTAssertLessThan(median(samples), Self.tapBudget, "median \(median(samples) * 1000) ms: tap to feedback must stay under 100 ms")
    }

    /// Same tap, but the very first one after launch (audio session, first decode of everything).
    func testFirstTapAfterLaunch() throws {
        let (store, _, cards) = try makeBoard()
        let window = makeWindow(store: store)
        defer { window.isHidden = true }
        mainThreadBusyTime {}
        var syncPart: TimeInterval = 0
        let first = mainThreadBusyTime {
            let t0 = CACurrentMediaTime()
            store.tap(cards[0])
            syncPart = CACurrentMediaTime() - t0
        }
        report("firstTap500", [first])
        report("firstTap500SyncPartOfTap", [syncPart])
        XCTAssertLessThan(syncPart, Self.tapBudget, "the tap call itself must return in under 100 ms")
        // `first` is reported but not asserted. The first audio start makes the system raise a
        // priority-inversion runtime warning inside Apple's audio code, and XCTest then spends
        // about 200 ms on the main thread symbolicating it, which would be counted here. The
        // tap call itself (`syncPart`) is the part this app controls.
    }

    /// Looking up every picture for the board, as the grid does on each refresh.
    func testPictureLookupFor500Cards() throws {
        let (store, _, cards) = try makeBoard()
        var samples: [TimeInterval] = []
        for _ in 0..<3 {
            samples.append(mainThreadBusyTime {
                for card in cards { _ = store.image(for: card) }
            })
        }
        report("pictureLookup500", samples)
        XCTAssertLessThan(median(samples), Self.lookupBudget, "median \(median(samples) * 1000) ms: picture lookup must be a memory read, not a disk decode")
    }
}
