import XCTest

/// Keyboard page: type with big keys, pick a prediction, add the words to the message bar.
final class KeyboardUITests: XCTestCase {
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

    func testTypePickPredictionAndAddToBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-ClearImportedBoard", "-KidMode", "-GoHome"]
        app.launch()
        let open = app.buttons["openKeyboard"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "no keyboard button in kid mode")
        open.tap()

        XCTAssertTrue(app.buttons["key-w"].waitForExistence(timeout: 5), "keyboard page didn't open")
        app.buttons["key-i"].tap()
        app.buttons["keySpace"].tap()
        app.buttons["key-w"].tap()
        app.buttons["key-a"].tap()
        let want = app.buttons["prediction-want"]
        XCTAssertTrue(want.waitForExistence(timeout: 3), "want is on the board, so it should be predicted")
        keep(app, "keyboard-wa")
        want.tap()
        XCTAssertEqual(app.descendants(matching: .any)["keyboardText"].value as? String, "i want ")

        app.buttons["keyboardAddToBar"].tap()
        XCTAssertFalse(app.buttons["key-w"].waitForExistence(timeout: 2), "keyboard closes after Add")
        let strip = app.descendants(matching: .any)["sentenceStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["want"].exists, "want is on the message bar")
        XCTAssertTrue(app.staticTexts["I"].exists, "I is on the message bar, capitalized")
        keep(app, "message-bar-typed")
        app.buttons["clearSentence"].tap()
    }
}
