import XCTest

/// Long-press a word on the board for its forms; picking one puts it on the message bar.
final class WordFormsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testLongPressOffersTensesAndAddsThePickedForm() {
        let app = XCUIApplication()
        app.launchArguments = ["-ClearImportedBoard", "-UnhideSlug", "go", "-KidMode"]
        app.launch()
        let go = app.descendants(matching: .any)["card-go"]
        XCTAssertTrue(go.waitForExistence(timeout: 20), "no go button")
        go.press(forDuration: 0.8)

        let went = app.buttons["wordForm-went"]
        XCTAssertTrue(went.waitForExistence(timeout: 5), "no word forms after long-press")
        XCTAssertTrue(app.buttons["wordForm-going"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "word-forms-go"
        shot.lifetime = .keepAlways
        add(shot)

        went.tap()
        XCTAssertFalse(app.buttons["wordForm-went"].waitForExistence(timeout: 2), "sheet closes")
        let strip = app.descendants(matching: .any)["sentenceStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue(strip.staticTexts["went"].exists || app.staticTexts["went"].exists, "went is on the message bar")
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "message-bar-went"
        after.lifetime = .keepAlways
        add(after)
        app.buttons["clearSentence"].tap()
    }
}
