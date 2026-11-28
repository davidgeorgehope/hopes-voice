import XCTest

/// Settings → Home screen → Core words shows a fixed core-word grid; tapping a word talks.
final class CoreWordsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// Never leave the core layout on for the tests that run after this one.
    override func tearDown() {
        let app = XCUIApplication()
        app.launchArguments = ["-HomeLayout", "myBoard", "-ClearRecents"]
        app.launch()
        app.terminate()
    }

    /// The core tile for a word: its own button when the board has one, else the core stand-in.
    private func coreTile(_ app: XCUIApplication, _ word: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", ["card-\(word)", "card-core:\(word)"]))
            .firstMatch
    }

    func testCoreWordHomeTalksAndCanBeTurnedOff() {
        let app = XCUIApplication()
        app.launchArguments = ["-ClearImportedBoard", "-HomeLayout", "coreWords", "-KidMode", "-GoHome"]
        app.launch()
        let you = coreTile(app, "you")
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
        XCTAssertFalse(coreTile(app, "you").exists, "core words are off")
    }
}
