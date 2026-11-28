import XCTest

/// Settings has Save a backup / Restore from a backup, and a backup file brings back a
/// renamed and a hidden button on the default board.
final class BackupUITests: XCTestCase {
    private static func fixture(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BestWishesTests/Fixtures/\(name).backup.json")
            .path
    }

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSettingsOffersBackupAndRestore() {
        let app = XCUIApplication()
        app.launchArguments = ["-ClearImportedBoard", "-EditMode", "-OpenSettings"]
        app.launch()
        let save = app.buttons["settingsBackupSave"]
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 15), "settings did not open")
        for _ in 0..<8 where !save.isHittable { list.swipeUp() }
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(app.buttons["settingsBackupRestore"].exists)
        keep(app, "settings-backup")
    }

    func testRestoringABackupBringsBackEdits() {
        let app = XCUIApplication()
        app.launchArguments = ["-ClearImportedBoard", "-RestoreBackup", Self.fixture("sample")]
        app.launch()
        let renamed = app.descendants(matching: .any)["card-car"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 20), "car button missing")
        XCTAssertTrue(renamed.label.contains("truck"), "label is \(renamed.label)")
        XCTAssertFalse(app.descendants(matching: .any)["card-door"].exists, "door should be hidden")
        keep(app, "restored-board")
        // Put the untouched default board back for the tests that run after this one.
        app.terminate()
        app.launchArguments = ["-ClearImportedBoard", "-RestoreBackup", Self.fixture("empty")]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["card-door"].waitForExistence(timeout: 20))
    }
}
