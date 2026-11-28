import XCTest

/// Settings → Home screen → Core words shows a fixed core-word grid; tapping a word talks.
final class CoreWordsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testCoreWordHomeTalksAndCanBeTurnedOff() {
        let app = XCUIApplication()
        app.launchArguments = ["-ClearImportedBoard", "-HomeLayout", "coreWords", "-KidMode", "-GoHome"]
        app.launch()
        let you = app.descendants(matching: .any)["card-core:you"]
        XCTAssertTrue(you.waitForExistence(timeout: 20), "no core word tile for you")
        XCTAssertTrue(app.descendants(matching: .any)["card-want"].exists, "want uses its existing button")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "core-home"
        shot.lifetime = .keepAlways
        add(shot)

        you.tap()
        XCTAssertTrue(app.descendants(matching: .any)["sentenceStrip"].staticTexts["you"].waitForExistence(timeout: 5)
                      || app.staticTexts["you"].exists)
        app.buttons["clearSentence"].tap()

        app.terminate()
        app.launchArguments = ["-HomeLayout", "myBoard", "-KidMode", "-GoHome"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["card-car"].waitForExistence(timeout: 20), "back to the family's board")
        XCTAssertFalse(app.descendants(matching: .any)["card-core:you"].exists)
    }
}
