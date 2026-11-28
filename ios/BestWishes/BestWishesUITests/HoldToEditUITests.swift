import XCTest

/// Regression tests for issue #28: holding the toolbar Edit lock must switch to Edit mode
/// as soon as the hold completes, with no navigation (such as tapping Home) in between.
final class HoldToEditUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchKidMode(live: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // Offline, empty board, kid mode: nothing else on screen can change state.
        app.launchArguments = live ? ["-KidMode"] : ["-KidMode", "-UIEmptyBoard", "-APIBaseURL", "http://127.0.0.1:9"]
        app.launch()
        return app
    }

    func testOneFingerHoldEntersEditWithoutNavigation() {
        let app = launchKidMode()
        let lock = app.descendants(matching: .any)["editLock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 10), "kid-mode Edit lock should be visible")
        XCTAssertFalse(app.buttons["doneEditing"].exists)

        lock.press(forDuration: 2.2)

        XCTAssertTrue(
            app.buttons["doneEditing"].waitForExistence(timeout: 2),
            "Edit chrome (Done) must appear right after the hold, without tapping Home"
        )
        XCTAssertFalse(app.descendants(matching: .any)["editLock"].exists)
    }

    /// Accessibility queries can force a SwiftUI refresh, so also check what is actually on screen.
    func testScreenPixelsChangeAfterHoldWithoutAnyQuery() throws {
        try screenChangesAfterHold(live: false)
    }

    func testScreenPixelsChangeAfterHoldOnLiveBoard() throws {
        try screenChangesAfterHold(live: true)
    }

    private func screenChangesAfterHold(live: Bool) throws {
        let app = launchKidMode(live: live)
        let lock = app.descendants(matching: .any)["editLock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        let before = app.screenshot().image
        lock.press(forDuration: 2.2)
        Thread.sleep(forTimeInterval: 1)
        let after = app.screenshot().image
        for (name, image) in [("before", before), ("after", after)] {
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let change = Self.changedFraction(before, after)
        XCTAssertGreaterThan(change, 0.01, "screen did not visibly change after the hold (changed \(change))")
    }

    private static func changedFraction(_ a: UIImage, _ b: UIImage) -> Double {
        func pixels(_ image: UIImage) -> [UInt8]? {
            guard let cg = image.cgImage else { return nil }
            let w = 64, h = 128
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let ok = data.withUnsafeMutableBytes { buffer -> Bool in
                guard let ctx = CGContext(
                    data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            return ok ? data : nil
        }
        guard let pa = pixels(a), let pb = pixels(b), pa.count == pb.count else { return 1 }
        var differing = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            let d = abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1])) + abs(Int(pa[i + 2]) - Int(pb[i + 2]))
            if d > 40 { differing += 1 }
        }
        return Double(differing) / Double(pa.count / 4)
    }

    func testShortTapDoesNotEnterEdit() {
        let app = launchKidMode()
        let lock = app.descendants(matching: .any)["editLock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 10))
        lock.tap()
        XCTAssertFalse(app.buttons["doneEditing"].waitForExistence(timeout: 1))
        XCTAssertTrue(lock.exists)
    }

    func testDoneReturnsToKidMode() {
        let app = launchKidMode()
        let lock = app.descendants(matching: .any)["editLock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 10))
        lock.press(forDuration: 2.2)
        let done = app.buttons["doneEditing"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editLock"].waitForExistence(timeout: 2))
    }

    func testSecondHoldAfterDoneEntersEditAgain() {
        let app = launchKidMode(live: true)
        for round in 1...2 {
            let lock = app.descendants(matching: .any)["editLock"]
            XCTAssertTrue(lock.waitForExistence(timeout: 10), "round \(round): lock visible")
            lock.press(forDuration: 2.0)
            let done = app.buttons["doneEditing"]
            XCTAssertTrue(done.waitForExistence(timeout: 2), "round \(round): Done visible after hold")
            done.tap()
        }
    }

    func testHoldOnEditButtonWhenCaregiverAlreadyUnlocked() {
        let app = XCUIApplication()
        app.launchArguments = ["-CaregiverMode"]
        app.launch()
        let edit = app.buttons["editBoard"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.press(forDuration: 2.0)
        XCTAssertTrue(app.buttons["doneEditing"].waitForExistence(timeout: 2))
    }

    func testHoldJustPastThresholdThenQuickLift() {
        let app = launchKidMode(live: true)
        for (round, duration) in [1.55, 1.7].enumerated() {
            let lock = app.descendants(matching: .any)["editLock"]
            XCTAssertTrue(lock.waitForExistence(timeout: 10), "round \(round)")
            lock.press(forDuration: duration)
            Thread.sleep(forTimeInterval: 0.6)
            let after = app.screenshot().image
            XCTAssertNotNil(after)
            XCTAssertTrue(app.buttons["doneEditing"].waitForExistence(timeout: 2), "round \(round) at \(duration)s")
            app.buttons["doneEditing"].tap()
        }
    }
}
