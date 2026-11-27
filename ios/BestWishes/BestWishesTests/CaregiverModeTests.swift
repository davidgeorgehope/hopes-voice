import XCTest
@testable import BestWishes

@MainActor
final class CaregiverModeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "bw-caregiver-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMissingPreferenceDefaultsToKidAndHidesAddChrome() {
        XCTAssertNil(defaults.object(forKey: CaregiverMode.defaultsKey))

        let mode = CaregiverMode(defaults: defaults)

        XCTAssertFalse(mode.isCaregiver)
        XCTAssertFalse(mode.showsAddChrome)
    }

    func testUnlockShowsAddChromeAndLockHidesItAgain() {
        let mode = CaregiverMode(defaults: defaults)
        XCTAssertFalse(mode.showsAddChrome)

        mode.unlock()
        XCTAssertTrue(mode.isCaregiver)
        XCTAssertTrue(mode.showsAddChrome)

        mode.lock()
        XCTAssertFalse(mode.isCaregiver)
        XCTAssertFalse(mode.showsAddChrome)
    }

    func testPreferenceRoundTripsThroughUserDefaults() {
        let mode = CaregiverMode(defaults: defaults)
        mode.unlock()

        let reopened = CaregiverMode(defaults: defaults)
        XCTAssertTrue(reopened.isCaregiver)
        XCTAssertTrue(reopened.showsAddChrome)

        mode.lock()
        let locked = CaregiverMode(defaults: defaults)
        XCTAssertFalse(locked.isCaregiver)
        XCTAssertFalse(locked.showsAddChrome)
    }

    func testInitReadsExistingTruePreference() {
        defaults.set(true, forKey: CaregiverMode.defaultsKey)

        let mode = CaregiverMode(defaults: defaults)

        XCTAssertTrue(mode.isCaregiver)
        XCTAssertTrue(mode.showsAddChrome)
    }

    func testUnlockHoldDurationIsOneAndAHalfSeconds() {
        XCTAssertEqual(CaregiverMode.unlockHoldDuration, 1.5)
    }

    func testKidModeHidesProfileSwitcherAndUnlockShowsIt() {
        let mode = CaregiverMode(defaults: defaults)
        XCTAssertFalse(mode.showsProfileSwitcher)
        XCTAssertFalse(mode.showsSearchChrome)
        XCTAssertFalse(mode.showsVoiceChrome)

        mode.unlock()
        XCTAssertTrue(mode.showsProfileSwitcher)
        XCTAssertTrue(mode.showsSearchChrome)
        XCTAssertTrue(mode.showsVoiceChrome)

        mode.lock()
        XCTAssertFalse(mode.showsProfileSwitcher)
        XCTAssertFalse(mode.showsSearchChrome)
        XCTAssertFalse(mode.showsVoiceChrome)
    }

    func testKidModeHidesVoiceChromeAndUnlockShowsIt() {
        let mode = CaregiverMode(defaults: defaults)
        XCTAssertFalse(mode.isCaregiver)
        XCTAssertFalse(mode.showsVoiceChrome)

        mode.unlock()
        XCTAssertTrue(mode.showsVoiceChrome)

        mode.lock()
        XCTAssertFalse(mode.showsVoiceChrome)

        mode.applyLaunchArguments(["-CaregiverMode"])
        XCTAssertTrue(mode.showsVoiceChrome)

        mode.applyLaunchArguments(["-KidMode"])
        XCTAssertFalse(mode.showsVoiceChrome)
    }

    func testLaunchArgsCallTheSameUnlockAndLock() {
        let mode = CaregiverMode(defaults: defaults)
        XCTAssertFalse(mode.showsAddChrome)

        mode.applyLaunchArguments(["-CaregiverMode"])
        XCTAssertTrue(mode.showsAddChrome)

        mode.applyLaunchArguments(["-KidMode"])
        XCTAssertFalse(mode.showsAddChrome)
    }

    func testLockClearsEditState() {
        let mode = CaregiverMode(defaults: defaults)
        mode.unlock()
        mode.enterEdit()
        XCTAssertTrue(mode.showsEditChrome)

        mode.lock()
        XCTAssertFalse(mode.isEditing)
        XCTAssertFalse(mode.showsEditChrome)
        XCTAssertFalse(mode.showsEditButton)
    }
}
