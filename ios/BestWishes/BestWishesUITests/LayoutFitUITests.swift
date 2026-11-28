import XCTest

/// Every button, core word, and message-bar control must sit inside the screen width on every
/// device and orientation, and the default board must fill the height instead of leaving
/// half the screen empty. Regression for the iPhone layout where one too-wide row (the
/// caregiver profile switcher) widened the whole board until cells ran off both edges.
final class LayoutFitUITests: XCTestCase {
    private static let sampleBoard: String = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BestWishesTests/Fixtures/sample.board.json")
            .path
    }()

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private static let fitPredicate = NSPredicate(format: """
        identifier BEGINSWITH 'card-' OR identifier BEGINSWITH 'folder-' \
        OR identifier BEGINSWITH 'coreWord-' OR identifier BEGINSWITH 'recentWord-' \
        OR identifier BEGINSWITH 'emptyCell-' \
        OR identifier IN {'speakSentence', 'clearSentence', 'backspaceSentence', 'coreRow', 'sentenceStrip'}
        """)

    /// Returns the board cells it checked.
    @discardableResult
    private func assertEverythingFitsWidth(
        _ app: XCUIApplication,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [CGRect] {
        let window = app.windows.firstMatch.frame
        XCTAssertFalse(window.isEmpty, "\(context): no window", file: file, line: line)
        let elements = app.descendants(matching: .any).matching(Self.fitPredicate).allElementsBoundByIndex
        XCTAssertFalse(elements.isEmpty, "\(context): nothing on screen to check", file: file, line: line)
        // SwiftUI can repeat a cell's identifier on its picture and label, so check the
        // union of everything that carries one identifier.
        var frames: [String: CGRect] = [:]
        for element in elements {
            let frame = element.frame
            guard !frame.isEmpty else { continue }
            frames[element.identifier] = frames[element.identifier].map { $0.union(frame) } ?? frame
        }
        var cells: [CGRect] = []
        for (id, frame) in frames {
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 1, "\(context): \(id) starts off the left edge (\(frame) in \(window))", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 1, "\(context): \(id) runs off the right edge (\(frame) in \(window))", file: file, line: line)
            if id.hasPrefix("card-") || id.hasPrefix("folder-") || id.hasPrefix("emptyCell-") {
                cells.append(frame)
            }
        }
        return cells
    }

    private func waitForBoard(_ app: XCUIApplication, cell: String = "card-") {
        let any = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", cell)).firstMatch
        XCTAssertTrue(any.waitForExistence(timeout: 20), "board never showed a \(cell) cell")
        Thread.sleep(forTimeInterval: 1)
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testDefaultHomeFitsAndFillsTheScreen() {
        let app = launch(["-KidMode", "-ClearImportedBoard"])
        waitForBoard(app)
        attachScreenshot("home-portrait")
        let cells = assertEverythingFitsWidth(app, "home portrait")
        let window = app.windows.firstMatch.frame
        // Rows wholly below the screen are scrolled away (iPad shows whole rows only); a row that
        // starts on screen must end on screen.
        let onScreen = cells.filter { $0.minY < window.maxY - 1 }
        guard let lowest = onScreen.map(\.maxY).max() else { return XCTFail("no cells") }
        XCTAssertLessThanOrEqual(lowest, window.maxY + 1, "a home-board row is cut off at the bottom")
        XCTAssertGreaterThan(lowest, window.maxY - window.height * 0.12, "the board leaves the bottom of the screen empty")
        let widths = Set(cells.map { Int($0.width.rounded()) })
        // Folder tabs report a slightly narrower frame than word cells.
        XCTAssertLessThanOrEqual((widths.max() ?? 0) - (widths.min() ?? 0), 8, "board cells are not all the same width: \(widths)")
    }

    func testDefaultFolderFits() {
        let app = launch(["-KidMode", "-ClearImportedBoard", "-OpenFolder", "food"])
        waitForBoard(app)
        attachScreenshot("food-portrait")
        assertEverythingFitsWidth(app, "food folder portrait")
    }

    func testLandscapeAndBackStillFits() {
        let app = launch(["-KidMode", "-ClearImportedBoard", "-OpenFolder", "food"])
        waitForBoard(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        attachScreenshot("food-landscape")
        assertEverythingFitsWidth(app, "food folder landscape")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.5)
        attachScreenshot("food-portrait-after-rotation")
        assertEverythingFitsWidth(app, "food folder back in portrait")
    }

    /// The caregiver row is wider than a phone. It must scroll on its own, not widen the board,
    /// and the board must still fit after locking back to kid mode.
    func testCaregiverModeThenLockStillFits() {
        let app = launch(["-CaregiverMode", "-ClearImportedBoard"])
        waitForBoard(app)
        attachScreenshot("caregiver")
        assertEverythingFitsWidth(app, "caregiver mode")
        let lock = app.buttons["lockCaregiver"]
        if lock.waitForExistence(timeout: 5) {
            if !lock.isHittable { app.scrollViews.firstMatch.swipeLeft() }
            lock.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        attachScreenshot("after-lock")
        assertEverythingFitsWidth(app, "kid mode after caregiver")
    }

    func testImportedSampleBoardFits() {
        let app = launch(["-KidMode", "-ImportBoard", Self.sampleBoard])
        waitForBoard(app, cell: "folder-")
        attachScreenshot("imported-sample")
        let cells = assertEverythingFitsWidth(app, "imported sample board")
        let window = app.windows.firstMatch.frame
        for cell in cells {
            XCTAssertLessThanOrEqual(cell.maxY, window.maxY + 1, "imported cell cut off at the bottom: \(cell)")
        }
    }
}
