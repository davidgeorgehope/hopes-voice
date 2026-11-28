import XCTest

/// Phrases page: say a saved sentence, put it on the message bar, save the bar as a new phrase.
final class PhrasesUITests: XCTestCase {
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

    func testSayPutOnBarAndSaveTheBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-ClearImportedBoard", "-KidMode", "-GoHome", "-ResetPhrases"]
        app.launch()
        let open = app.buttons["openPhrases"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "no Phrases button in kid mode")
        open.tap()

        let first = app.buttons["phrase-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), "phrases page didn't open")
        XCTAssertFalse(app.buttons["phraseDelete-0"].exists, "kid mode can't delete phrases")
        XCTAssertFalse(app.buttons["phrasesSaveBar"].exists, "nothing to save while the bar is empty")
        keep(app, "phrases")
        first.tap()

        app.buttons["phraseToBar-0"].tap()
        XCTAssertTrue(app.staticTexts["I need help"].waitForExistence(timeout: 5), "the whole phrase is one chip on the bar")
        keep(app, "phrase-on-bar")

        app.buttons["openKeyboard"].tap()
        XCTAssertTrue(app.buttons["key-n"].waitForExistence(timeout: 5))
        for letter in ["n", "o", "w"] { app.buttons["key-\(letter)"].tap() }
        app.buttons["keyboardAddToBar"].tap()
        XCTAssertTrue(app.staticTexts["now"].waitForExistence(timeout: 5))

        open.tap()
        let save = app.buttons["phrasesSaveBar"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the bar can be saved as a phrase")
        save.tap()
        XCTAssertTrue(app.buttons["Say I need help now"].waitForExistence(timeout: 3), "saved phrase is listed")
        keep(app, "phrase-saved")
        app.buttons["phrasesClose"].tap()
        app.buttons["clearSentence"].tap()
    }
}
