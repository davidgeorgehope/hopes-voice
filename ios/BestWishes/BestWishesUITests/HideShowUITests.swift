import XCTest

/// Edit → tap a button → turn off "Show on the board" → Save: the button stays in its spot,
/// dimmed with a hidden mark, and is gone from the child's board until it is shown again.
final class HideShowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func setVisible(_ app: XCUIApplication, _ slug: String, _ visible: Bool) {
        let card = app.descendants(matching: .any)["card-\(slug)"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "no \(slug) button")
        card.tap()
        let toggle = app.switches["editorVisible"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "editor has no Show switch")
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        let isOn = (toggle.value as? String) == "1"
        if isOn != visible { toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap() }
        XCTAssertEqual(toggle.value as? String, visible ? "1" : "0")
        app.buttons["editorSave"].tap()
        XCTAssertFalse(app.switches["editorVisible"].waitForExistence(timeout: 2))
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testHideThenShowWithoutDeleting() {
        let app = XCUIApplication()
        // Start from the default board with nothing hidden.
        app.launchArguments = ["-ClearImportedBoard", "-UnhideSlug", "car", "-EditMode"]
        app.launch()

        setVisible(app, "car", false)
        let car = app.descendants(matching: .any)["card-car"]
        XCTAssertTrue(car.waitForExistence(timeout: 5), "hidden button still shows in Edit")
        XCTAssertEqual(car.value as? String, "Hidden")
        keep(app, "edit-hidden-car")

        app.terminate()
        app.launchArguments = ["-KidMode"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["card-door"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["card-car"].exists, "hidden from the child")
        keep(app, "kid-without-car")

        app.terminate()
        app.launchArguments = ["-EditMode"]
        app.launch()
        setVisible(app, "car", true)
        app.terminate()
        app.launchArguments = ["-KidMode"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["card-car"].waitForExistence(timeout: 20), "shown again")
    }
}
