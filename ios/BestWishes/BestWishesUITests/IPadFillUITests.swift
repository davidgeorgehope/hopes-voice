import XCTest

/// iPad board buttons must keep a usable shape (not short, wide strips with a tiny picture)
/// in portrait and landscape, on the default board and on an imported board.
/// Set TEST_RUNNER_HV_IMPORT_BOARD to a board file or folder to check a family's own board;
/// otherwise the public sample board is used.
final class IPadFillUITests: XCTestCase {
    private static let sampleBoard: String = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BestWishesTests/Fixtures/sample.board.json")
            .path
    }()

    private static var importBoard: String {
        let path = ProcessInfo.processInfo.environment["HV_IMPORT_BOARD"] ?? ""
        return path.isEmpty ? sampleBoard : path
    }

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func check(_ name: String, args: [String], orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        let any = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'card-' OR identifier BEGINSWITH 'folder-'"))
        XCTAssertTrue(any.firstMatch.waitForExistence(timeout: 25), "\(name): no board")
        XCUIDevice.shared.orientation = orientation
        Thread.sleep(forTimeInterval: 2)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)

        var frames: [String: CGRect] = [:]
        for element in any.allElementsBoundByIndex {
            let f = element.frame
            guard !f.isEmpty else { continue }
            frames[element.identifier] = frames[element.identifier].map { $0.union(f) } ?? f
        }
        let window = app.windows.firstMatch.frame
        let onScreen = frames.values.filter { window.intersects($0) }
        XCTAssertFalse(onScreen.isEmpty, "\(name): no cells on screen")
        let ratios = onScreen.map { $0.height / max($0.width, 1) }.sorted()
        let median = ratios[ratios.count / 2]
        let shortest = onScreen.map(\.height).min() ?? 0
        print("FILL \(name) cells=\(onScreen.count) medianHeightToWidth=\(String(format: "%.2f", median)) minHeight=\(Int(shortest))")
        guard isPad else { return }
        // A button reads well when it's no flatter than about 2:1 and tall enough for a picture.
        XCTAssertGreaterThanOrEqual(median, 0.5, "\(name): buttons are squashed (height/width \(median))")
        XCTAssertGreaterThanOrEqual(shortest, 90, "\(name): buttons too short for a picture (\(shortest) pt)")
        app.terminate()
    }

    func testDefaultBoardPortraitAndLandscape() {
        check("default-portrait", args: ["-ClearImportedBoard", "-KidMode", "-GoHome"], orientation: .portrait)
        check("default-landscape", args: ["-ClearImportedBoard", "-KidMode", "-GoHome"], orientation: .landscapeLeft)
    }

    func testImportedBoardPortraitAndLandscape() {
        check("imported-portrait", args: ["-KidMode", "-ImportBoard", Self.importBoard], orientation: .portrait)
        check("imported-landscape", args: ["-KidMode", "-ImportBoard", Self.importBoard], orientation: .landscapeLeft)
        // Leave the next test with the default board.
        let app = XCUIApplication()
        app.launchArguments = ["-ClearImportedBoard"]
        app.launch()
        app.terminate()
    }
}
