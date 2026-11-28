import XCTest

/// In Edit, an existing word button offers "New picture" (not "Generate"), and choosing it shows
/// that a new picture will be made on Save instead of the old one. Cancel spends nothing.
final class NewPictureUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testExistingButtonOffersNewPicture() {
        let app = XCUIApplication()
        app.launchArguments = ["-ClearImportedBoard", "-EditMode"]
        app.launch()

        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'card-'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "no word button on the board")
        card.tap()

        let generate = app.buttons["editorGenerate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 10), "button editor did not open")
        XCTAssertTrue(app.buttons["editorKeepPicture"].exists)
        XCTAssertTrue(generate.label.contains("New picture"), "chip says \(generate.label)")
        generate.tap()
        XCTAssertTrue(app.staticTexts["New AI picture on save"].waitForExistence(timeout: 5))

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "editor-new-picture"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["editorCancel"].tap()
        XCTAssertFalse(app.buttons["editorGenerate"].waitForExistence(timeout: 2))
    }
}
