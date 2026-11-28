import UIKit
import XCTest
@testable import BestWishes

/// Backup / restore of the whole vocabulary: one file carries every profile's board, edits,
/// on-device pictures, and settings to a fresh device, and a bad file changes nothing.
@MainActor
final class VocabularyBackupTests: XCTestCase {
    private var roots: [URL] = []
    private var suites: [String] = []

    override func tearDown() {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        suites.forEach { UserDefaults().removePersistentDomain(forName: $0) }
    }

    private func device() throws -> (AssetCache, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let suite = "bw-backup-\(UUID().uuidString)"
        suites.append(suite)
        return (AssetCache(root: root), UserDefaults(suiteName: suite)!)
    }

    private func photo(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private static let sampleBoard = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/sample.board.json")

    /// Old device: edits on both profiles, a caregiver photo, settings, grid size, recents.
    private func seededOldDevice() throws -> (AssetCache, UserDefaults) {
        let (cache, defaults) = try device()
        cache.saveLabelOverlays(["juice": "apple juice"], for: .child1)
        cache.saveHiddenSlugs(["car"], for: .child1)
        cache.saveSpeakOverlays(["juice": "I want juice please"], for: .child1)
        cache.saveStyleOverlays(["juice": CellStyle(backgroundHex: "#93C47D", borderHex: "#111111")], for: .child1)
        cache.saveLabelOverlays(["dog": "puppy"], for: .child2)
        cache.saveCards([Card(word: "grandma", slug: "grandma", imageURL: "", audioURL: "")])
        XCTAssertTrue(cache.saveLocalImage(photo(.red), for: "grandma"))
        var settings = ProfileSettings.default
        settings.colorScheme = "custom"
        cache.saveProfileSettings(settings, for: .child2)
        cache.saveRecents(["juice", "car"], for: .child1)
        defaults.set(5, forKey: GridLayout.rowsKey(for: .child1))
        defaults.set(7, forKey: GridLayout.columnsKey(for: .child1))
        return (cache, defaults)
    }

    func testBackupCarriesEverythingToAFreshDevice() throws {
        let (oldCache, oldDefaults) = try seededOldDevice()
        let oldStore = CardStore(cache: oldCache, player: SpeechPlayer())
        let data = try oldStore.makeBackupData(defaults: oldDefaults)

        let (cache, defaults) = try device()
        let store = CardStore(cache: cache, player: SpeechPlayer())
        let backup = try store.restoreBackup(data, defaults: defaults)

        XCTAssertEqual(backup.profiles.count, KidProfile.allCases.count)
        XCTAssertEqual(store.labelOverlays["juice"], "apple juice")
        XCTAssertEqual(store.hiddenSlugs, ["car"])
        XCTAssertEqual(store.speakText(for: Card(word: "juice", slug: "juice", imageURL: "", audioURL: "")), "I want juice please")
        XCTAssertEqual(store.styleOverlays["juice"]?.backgroundHex, "#93C47D")
        XCTAssertEqual(store.recentSlugs, ["juice", "car"])
        XCTAssertEqual(cache.loadLabelOverlays(for: .child2), ["dog": "puppy"])
        XCTAssertEqual(cache.loadProfileSettings(for: .child2).colorScheme, "custom")
        XCTAssertTrue(cache.isLocalImage("grandma"))
        XCTAssertEqual(try Data(contentsOf: cache.imageURL(for: "grandma")), try Data(contentsOf: oldCache.imageURL(for: "grandma")))
        XCTAssertEqual(defaults.integer(forKey: GridLayout.rowsKey(for: .child1)), 5)
        XCTAssertEqual(GridLayout(defaults: defaults, profile: .child1).columnCount, 7)
        XCTAssertNotNil(store.banner)
    }

    func testImportedBoardComesBackWithItsCells() throws {
        let (oldCache, oldDefaults) = try device()
        let oldStore = CardStore(cache: oldCache, player: SpeechPlayer())
        let raw = try Data(contentsOf: Self.sampleBoard)
        oldStore.applyImportedDocument(try BoardImport.decode(raw), raw: raw, bundle: nil)
        XCTAssertTrue(oldStore.hasImportedBoard)
        let data = try oldStore.makeBackupData(defaults: oldDefaults)

        let (cache, defaults) = try device()
        let store = CardStore(cache: cache, player: SpeechPlayer())
        XCTAssertFalse(store.hasImportedBoard)
        try store.restoreBackup(data, defaults: defaults)

        XCTAssertTrue(store.hasImportedBoard)
        XCTAssertEqual(store.importedDocument?.boards.count, oldStore.importedDocument?.boards.count)
        XCTAssertEqual(Set(store.cards.map(\.slug)), Set(oldStore.cards.map(\.slug)))
        XCTAssertEqual(store.settings, oldStore.settings)
    }

    func testRestoringABackupWithoutAnImportRemovesTheImport() throws {
        let (oldCache, oldDefaults) = try seededOldDevice()
        let data = try CardStore(cache: oldCache, player: SpeechPlayer()).makeBackupData(defaults: oldDefaults)

        let (cache, defaults) = try device()
        let store = CardStore(cache: cache, player: SpeechPlayer())
        let raw = try Data(contentsOf: Self.sampleBoard)
        store.applyImportedDocument(try BoardImport.decode(raw), raw: raw, bundle: nil)
        try store.restoreBackup(data, defaults: defaults)

        XCTAssertFalse(store.hasImportedBoard)
        XCTAssertNil(cache.loadImportedBoard(for: .child1))
        XCTAssertEqual(store.labelOverlays["juice"], "apple juice")
    }

    func testPhotosNoBoardUsesAnyMoreAreLeftOut() throws {
        let (cache, defaults) = try device()
        cache.saveCards([Card(word: "grandma", slug: "grandma", imageURL: "", audioURL: "")])
        XCTAssertTrue(cache.saveLocalImage(photo(.red), for: "grandma"))
        XCTAssertTrue(cache.saveLocalImage(photo(.blue), for: "old-import:0:0"))

        let backup = VocabularyBackupIO.make(cache: cache, defaults: defaults)

        XCTAssertEqual(Set(backup.profiles["child1"].map { Array($0.doc.images.keys) } ?? []), ["grandma"])
        XCTAssertEqual(backup.pictures.count, 1)
    }

    func testDamagedOrForeignFilesChangeNothing() throws {
        let (oldCache, oldDefaults) = try seededOldDevice()
        var backup = VocabularyBackupIO.make(cache: oldCache, defaults: oldDefaults)
        let sha = try XCTUnwrap(backup.pictures.keys.first)
        backup.pictures[sha] = Data("not the picture".utf8)
        let damaged = try VocabularyBackupIO.encode(backup)

        let (cache, defaults) = try device()
        cache.saveLabelOverlays(["milk": "milk"], for: .child1)
        let store = CardStore(cache: cache, player: SpeechPlayer())

        XCTAssertThrowsError(try store.restoreBackup(damaged, defaults: defaults)) { error in
            XCTAssertEqual(error as? BackupError, .missingPicture("grandma"))
        }
        XCTAssertThrowsError(try store.restoreBackup(Data(contentsOf: Self.sampleBoard), defaults: defaults)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
        XCTAssertEqual(cache.loadLabelOverlays(for: .child1), ["milk": "milk"])
        XCTAssertEqual(store.labelOverlays, ["milk": "milk"])
        XCTAssertFalse(cache.isLocalImage("grandma"))
    }
}
