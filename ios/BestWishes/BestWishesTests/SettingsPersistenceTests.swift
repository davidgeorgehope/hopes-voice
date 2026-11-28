import XCTest
@testable import BestWishes

@MainActor
final class SettingsPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var cacheRoot: URL!
    private var cache: AssetCache!
    private var store: CardStore!
    private var grid: GridLayout!
    private var profiles: ProfileStore!

    override func setUp() {
        super.setUp()
        suiteName = "bw-settings-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bw-settings-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        cache = AssetCache(root: cacheRoot)
        profiles = ProfileStore(defaults: defaults)
        store = CardStore(cache: cache, player: SpeechPlayer(), profile: profiles.active)
        grid = GridLayout(defaults: defaults, profile: profiles.active)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        if let cacheRoot {
            try? FileManager.default.removeItem(at: cacheRoot)
        }
        cacheRoot = nil
        super.tearDown()
    }

    private func sampleURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.board.json")
    }

    private func relaunch(profile: KidProfile) -> (store: CardStore, grid: GridLayout, profiles: ProfileStore) {
        let profiles = ProfileStore(defaults: defaults)
        let grid = GridLayout(defaults: defaults, profile: profile)
        let store = CardStore(cache: cache, player: SpeechPlayer(), profile: profile)
        return (store, grid, profiles)
    }

    func testSaveHelperPersistsEverySettingAcrossRelaunch() {
        grid.setColumnCount(4)
        grid.setRowCount(6)
        var draft = BoardSettingsSheet.initialDraft(store: store, grid: grid)
        draft.viewportRows = 5
        draft.viewportCols = 3
        draft.backgroundHex = "112233"
        draft.colorMode = "border"
        draft.showCoreRow = false
        draft.showRecents = false
        draft.returnHomeAfterSelection = true
        draft.addFolderWordToBar = true
        draft.messageBar.style = "compactBlue"
        draft.messageBar.speakOnTap = false
        draft.messageBar.speakOnBarTap = false
        draft.messageBar.clearAfterSpeak = true
        draft.messageBar.textAboveImage = true
        draft.messageBar.showDeleteLast = false
        draft.messageBar.backgroundHex = "0000CB"
        draft.voice.engine = "server"
        draft.voice.rate = 0.75
        draft.voice.pitch = 1.25

        BoardSettingsSheet.apply(draft, store: store, grid: grid, profiles: profiles, displayName: "Star")

        let revived = relaunch(profile: .child1)
        XCTAssertEqual(revived.grid.rowCount, 5)
        XCTAssertEqual(revived.grid.columnCount, 3)
        XCTAssertEqual(revived.store.settings, draft)
        XCTAssertEqual(revived.store.settings.backgroundHex, "112233")
        XCTAssertEqual(revived.store.settings.colorMode, "border")
        XCTAssertFalse(revived.store.settings.showCoreRow)
        XCTAssertFalse(revived.store.settings.showRecents)
        XCTAssertTrue(revived.store.settings.returnHomeAfterSelection)
        XCTAssertEqual(revived.store.settings.messageBar.style, "compactBlue")
        XCTAssertFalse(revived.store.settings.messageBar.speakOnTap)
        XCTAssertFalse(revived.store.settings.messageBar.speakOnBarTap)
        XCTAssertTrue(revived.store.settings.messageBar.clearAfterSpeak)
        XCTAssertTrue(revived.store.settings.messageBar.textAboveImage)
        XCTAssertFalse(revived.store.settings.messageBar.showDeleteLast)
        XCTAssertEqual(revived.store.messageBar, draft.messageBar)
        XCTAssertEqual(revived.store.settings.voice.engine, "server")
        XCTAssertEqual(revived.store.settings.voice.rate, 0.75, accuracy: 0.001)
        XCTAssertEqual(revived.store.settings.voice.pitch, 1.25, accuracy: 0.001)
        XCTAssertFalse(revived.store.hasImportedBoard)
        XCTAssertEqual(revived.profiles.displayName(for: .child1), "Star")
    }

    func testChildProfilesKeepSeparateSettingsAndNames() {
        var child1 = BoardSettingsSheet.initialDraft(store: store, grid: grid)
        child1.viewportRows = 5
        child1.viewportCols = 3
        child1.backgroundHex = "111111"
        child1.colorMode = "fill"
        child1.showCoreRow = false
        child1.showRecents = false
        child1.returnHomeAfterSelection = true
        child1.messageBar.style = "compactBlue"
        child1.messageBar.speakOnTap = false
        child1.voice.engine = "server"
        child1.voice.rate = 0.75
        child1.voice.pitch = 1.25
        BoardSettingsSheet.apply(child1, store: store, grid: grid, profiles: profiles, displayName: "Star")

        profiles.switchTo(.child2, overlay: store, grid: grid)
        var child2 = BoardSettingsSheet.initialDraft(store: store, grid: grid)
        child2.viewportRows = 8
        child2.viewportCols = 2
        child2.backgroundHex = "AAAAAA"
        child2.colorMode = "border"
        child2.showCoreRow = true
        child2.showRecents = true
        child2.returnHomeAfterSelection = false
        child2.messageBar.style = "standard"
        child2.messageBar.speakOnTap = true
        child2.voice.engine = "system"
        child2.voice.rate = 1.25
        child2.voice.pitch = 0.75
        BoardSettingsSheet.apply(child2, store: store, grid: grid, profiles: profiles, displayName: "Blue Team")

        let names = ProfileStore(defaults: defaults)
        XCTAssertEqual(names.displayName(for: .child1), "Star")
        XCTAssertEqual(names.displayName(for: .child2), "Blue Team")
        XCTAssertEqual(names.active, .child2)
        XCTAssertEqual(defaults.string(forKey: ProfileStore.defaultsKey), "Child 2")

        let revived1 = relaunch(profile: .child1)
        XCTAssertEqual(revived1.store.settings.backgroundHex, "111111")
        XCTAssertEqual(revived1.store.settings.colorMode, "fill")
        XCTAssertFalse(revived1.store.settings.showCoreRow)
        XCTAssertFalse(revived1.store.settings.showRecents)
        XCTAssertTrue(revived1.store.settings.returnHomeAfterSelection)
        XCTAssertEqual(revived1.store.settings.messageBar.style, "compactBlue")
        XCTAssertFalse(revived1.store.settings.messageBar.speakOnTap)
        XCTAssertEqual(revived1.store.settings.voice.engine, "server")
        XCTAssertEqual(revived1.grid.rowCount, 5)
        XCTAssertEqual(revived1.grid.columnCount, 3)

        let revived2 = relaunch(profile: .child2)
        XCTAssertEqual(revived2.store.settings.backgroundHex, "AAAAAA")
        XCTAssertEqual(revived2.store.settings.colorMode, "border")
        XCTAssertTrue(revived2.store.settings.showCoreRow)
        XCTAssertTrue(revived2.store.settings.showRecents)
        XCTAssertFalse(revived2.store.settings.returnHomeAfterSelection)
        XCTAssertEqual(revived2.store.settings.messageBar.style, "standard")
        XCTAssertTrue(revived2.store.settings.messageBar.speakOnTap)
        XCTAssertEqual(revived2.store.settings.voice.engine, "system")
        XCTAssertEqual(revived2.store.settings.voice.rate, 1.25, accuracy: 0.001)
        XCTAssertEqual(revived2.store.settings.voice.pitch, 0.75, accuracy: 0.001)
        XCTAssertEqual(revived2.grid.rowCount, 8)
        XCTAssertEqual(revived2.grid.columnCount, 2)
        XCTAssertNotEqual(revived1.store.settings, revived2.store.settings)
    }

    func testDisplayNameTrimsCapsResetsAndLeavesIdentity() {
        XCTAssertEqual(profiles.displayName(for: .child1), "Child 1")
        XCTAssertEqual(profiles.displayName(for: .child2), "Child 2")
        XCTAssertEqual(profiles.activeName, "Child 1")
        XCTAssertNil(defaults.string(forKey: "bestwishes.profileName.child1"))
        XCTAssertNil(defaults.string(forKey: "bestwishes.profileName.child2"))

        profiles.setDisplayName("  Star  \n", for: .child1)
        XCTAssertEqual(profiles.displayName(for: .child1), "Star")
        XCTAssertEqual(profiles.activeName, "Star")
        XCTAssertEqual(defaults.string(forKey: "bestwishes.profileName.child1"), "Star")

        let tooLong = String(repeating: "A", count: 30)
        profiles.setDisplayName("  \(tooLong)\n", for: .child2)
        let capped = String(repeating: "A", count: 24)
        XCTAssertEqual(profiles.displayName(for: .child2), capped)
        XCTAssertEqual(defaults.string(forKey: "bestwishes.profileName.child2"), capped)
        XCTAssertEqual(capped.count, ProfileStore.maxDisplayNameLength)

        let revived = ProfileStore(defaults: defaults)
        XCTAssertEqual(revived.displayName(for: .child1), "Star")
        XCTAssertEqual(revived.activeName, "Star")
        XCTAssertEqual(revived.displayName(for: .child2), capped)

        profiles.setDisplayName("   \n\t", for: .child1)
        XCTAssertNil(defaults.string(forKey: "bestwishes.profileName.child1"))
        XCTAssertEqual(profiles.displayName(for: .child1), "Child 1")
        XCTAssertEqual(profiles.activeName, "Child 1")
        let afterBlank = ProfileStore(defaults: defaults)
        XCTAssertEqual(afterBlank.displayName(for: .child1), "Child 1")
        XCTAssertEqual(afterBlank.activeName, "Child 1")

        profiles.setDisplayName("Blue Team", for: .child2)
        XCTAssertEqual(KidProfile.child1.rawValue, "Child 1")
        XCTAssertEqual(KidProfile.child2.rawValue, "Child 2")
        XCTAssertEqual(KidProfile(rawValue: "Child 2"), .child2)
        XCTAssertNil(KidProfile(rawValue: "Blue Team"))

        profiles.applyLaunchArguments(["-Profile", "Child 2"], overlay: store, grid: grid)
        XCTAssertEqual(profiles.active, .child2)
        XCTAssertEqual(defaults.string(forKey: ProfileStore.defaultsKey), "Child 2")
        XCTAssertEqual(profiles.activeName, "Blue Team")
        XCTAssertEqual(store.activeProfile, .child2)
    }

    func testNonImportedDraftUsesGridAndSaveDoesNotForceSixColumns() {
        XCTAssertEqual(store.settings.viewportCols, 6)
        XCTAssertEqual(store.settings.viewportRows, 4)
        grid.setColumnCount(4)
        grid.setRowCount(6)

        let draft = BoardSettingsSheet.initialDraft(store: store, grid: grid)
        XCTAssertEqual(draft.viewportCols, 4)
        XCTAssertEqual(draft.viewportRows, 6)
        XCTAssertEqual(BoardSettingsSheet.visibleRowRange(hasImportedBoard: false), GridLayout.allowedRowRange)
        XCTAssertEqual(BoardSettingsSheet.visibleRowRange(hasImportedBoard: false), 2...8)
        XCTAssertEqual(BoardSettingsSheet.visibleRowRange(hasImportedBoard: true), 2...12)

        BoardSettingsSheet.apply(draft, store: store, grid: grid, profiles: profiles, displayName: "")
        XCTAssertEqual(grid.columnCount, 4)
        XCTAssertEqual(grid.rowCount, 6)
        XCTAssertEqual(store.settings.viewportCols, 4)
        XCTAssertEqual(store.settings.viewportRows, 6)
        XCTAssertEqual(profiles.displayName(for: .child1), "Child 1")
        XCTAssertNil(defaults.string(forKey: "bestwishes.profileName.child1"))

        let revived = relaunch(profile: .child1)
        XCTAssertEqual(revived.grid.columnCount, 4)
        XCTAssertEqual(revived.grid.rowCount, 6)
    }

    func testImportedDraftKeepsViewportAndSaveDoesNotResizeGrid() throws {
        try store.importBoard(from: sampleURL())
        grid.setColumnCount(2)
        grid.setRowCount(8)
        XCTAssertEqual(store.settings.viewportRows, 4)
        XCTAssertEqual(store.settings.viewportCols, 6)

        let draft = BoardSettingsSheet.initialDraft(store: store, grid: grid)
        XCTAssertEqual(draft.viewportRows, 4)
        XCTAssertEqual(draft.viewportCols, 6)

        BoardSettingsSheet.apply(draft, store: store, grid: grid, profiles: nil, displayName: "Star")
        XCTAssertEqual(grid.columnCount, 2)
        XCTAssertEqual(grid.rowCount, 8)
        XCTAssertEqual(profiles.displayName(for: .child1), "Child 1")
    }

    func testPerBoardSizeOverrideSurvivesRelaunch() throws {
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: sampleURL())) as! [String: Any]
        var boards = object["boards"] as! [[String: Any]]
        boards[1]["rows"] = 7
        boards[1]["cols"] = 3
        object["boards"] = boards
        let url = cacheRoot.appendingPathComponent("override.board.json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        try store.importBoard(from: url)
        XCTAssertEqual(store.importedDocument?.profile.grid.rows, 4)
        XCTAssertEqual(store.importedDocument?.profile.grid.cols, 6)
        XCTAssertEqual(store.importedBoardRows, 6)
        XCTAssertEqual(store.importedBoardCols, 6)

        store.openFolder(id: "want")
        XCTAssertEqual(store.folderPath, ["food"])
        XCTAssertEqual(store.importedBoardRows, 7)
        XCTAssertEqual(store.importedBoardCols, 3)

        let revived = relaunch(profile: .child1)
        XCTAssertTrue(revived.store.hasImportedBoard)
        XCTAssertEqual(revived.store.folderPath, ["food"])
        XCTAssertEqual(revived.store.importedBoardRows, 7)
        XCTAssertEqual(revived.store.importedBoardCols, 3)
        XCTAssertEqual(revived.store.importedDocument?.profile.grid.rows, 4)
        XCTAssertEqual(revived.store.importedDocument?.profile.grid.cols, 6)
    }
}
