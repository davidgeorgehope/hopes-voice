import XCTest
@testable import BestWishes

@MainActor
final class GridLayoutTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "bw-grid-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMissingKeyDefaultsToThreeColumns() {
        XCTAssertNil(defaults.object(forKey: GridLayout.defaultsKey))

        let layout = GridLayout(defaults: defaults)

        XCTAssertEqual(layout.columnCount, 3)
        XCTAssertTrue(GridLayout.allowedCounts.contains(layout.columnCount))
        XCTAssertEqual(layout.gridItems.count, 3)
    }

    func testSetTwoThreeFourEachRoundTripThroughUserDefaults() {
        let layout = GridLayout(defaults: defaults)

        for count in [2, 3, 4] {
            layout.setColumnCount(count)

            XCTAssertEqual(layout.columnCount, count)
            XCTAssertEqual(defaults.integer(forKey: GridLayout.columnsKey(for: .child1)), count)

            let reopened = GridLayout(defaults: defaults)
            XCTAssertEqual(reopened.columnCount, count)
            XCTAssertEqual(reopened.gridItems.count, count)
        }
    }

    func testFreshInstanceReadsStoredCount() {
        defaults.set(2, forKey: GridLayout.defaultsKey)

        let layout = GridLayout(defaults: defaults)

        XCTAssertEqual(layout.columnCount, 2)
        XCTAssertEqual(layout.gridItems.count, 2)
    }

    func testValuesOutsideAllowedRangeCollapseToDefaultDensity() {
        let layout = GridLayout(defaults: defaults)

        for invalid in [0, 1, 9, 99, -1] {
            layout.setColumnCount(invalid)

            XCTAssertTrue(
                GridLayout.allowedColumnRange.contains(layout.columnCount),
                "\(invalid) produced \(layout.columnCount)"
            )
            XCTAssertFalse(GridLayout.allowedColumnRange.contains(invalid))
            XCTAssertEqual(layout.columnCount, GridLayout.defaultCount)
            XCTAssertEqual(layout.gridItems.count, layout.columnCount)
            XCTAssertNotEqual(layout.gridItems.count, invalid)
        }

        defaults.set(1, forKey: GridLayout.defaultsKey)
        let fromStored = GridLayout(defaults: defaults)
        XCTAssertTrue(GridLayout.allowedColumnRange.contains(fromStored.columnCount))
        XCTAssertEqual(fromStored.gridItems.count, fromStored.columnCount)
        XCTAssertNotEqual(fromStored.columnCount, 1)
        XCTAssertNotEqual(fromStored.columnCount, 9)
    }

    func testColumnsFiveAndSixAreValidDensities() {
        let layout = GridLayout(defaults: defaults)
        layout.setColumnCount(5)
        XCTAssertEqual(layout.columnCount, 5)
        XCTAssertEqual(layout.gridItems.count, 5)
        layout.setColumnCount(6)
        XCTAssertEqual(layout.columnCount, 6)
        XCTAssertEqual(layout.gridItems.count, 6)
    }

    func testBuildingGridYieldsThatManyColumns() {
        let layout = GridLayout(defaults: defaults)

        layout.setColumnCount(2)
        XCTAssertEqual(layout.gridItems.count, 2)

        layout.setColumnCount(3)
        XCTAssertEqual(layout.gridItems.count, 3)

        layout.setColumnCount(4)
        XCTAssertEqual(layout.gridItems.count, 4)
    }

    func testLaunchArgsCallTheSameSetter() {
        let layout = GridLayout(defaults: defaults)
        XCTAssertEqual(layout.columnCount, 3)

        layout.applyLaunchArguments(["-GridColumns", "2"])
        XCTAssertEqual(layout.columnCount, 2)
        XCTAssertEqual(defaults.integer(forKey: GridLayout.columnsKey(for: .child1)), 2)
        XCTAssertEqual(layout.gridItems.count, 2)

        let reopened = GridLayout(defaults: defaults)
        XCTAssertEqual(reopened.columnCount, 2)

        layout.applyLaunchArguments(["-GridColumns", "4"])
        XCTAssertEqual(layout.columnCount, 4)

        layout.applyLaunchArguments(["-GridColumns", "3"])
        XCTAssertEqual(layout.columnCount, 3)
    }

    func testLaunchArgOutsideRangeDoesNotProduceNinthDensity() {
        let layout = GridLayout(defaults: defaults)
        layout.applyLaunchArguments(["-GridColumns", "9"])
        XCTAssertEqual(layout.columnCount, 3)
        XCTAssertEqual(layout.gridItems.count, 3)
    }

    func testLaunchArgSetsFiveColumnsAndCustomRows() {
        let layout = GridLayout(defaults: defaults)
        layout.applyLaunchArguments(["-GridColumns", "5", "-GridRows", "6"])
        XCTAssertEqual(layout.columnCount, 5)
        XCTAssertEqual(layout.rowCount, 6)
    }

    func testSizeClassDefaultsApplyOnlyWhenNothingIsSaved() {
        let fresh = GridLayout(defaults: defaults)
        fresh.applySizeClassDefaultsIfNeeded(isCompact: false)
        XCTAssertEqual(fresh.columnCount, GridLayout.defaultPadColumns)
        XCTAssertEqual(fresh.rowCount, GridLayout.defaultPadRows)

        let phoneDefaults = UserDefaults(suiteName: "bw-grid-phone-\(UUID().uuidString)")!
        let phone = GridLayout(defaults: phoneDefaults)
        phone.applySizeClassDefaultsIfNeeded(isCompact: true)
        XCTAssertEqual(phone.columnCount, GridLayout.defaultPhoneColumns)
        XCTAssertEqual(phone.rowCount, GridLayout.defaultPhoneRows)

        // A saved 3-column board is left alone.
        let saved = GridLayout(defaults: defaults)
        saved.setColumnCount(3)
        saved.setRowCount(4)
        saved.applySizeClassDefaultsIfNeeded(isCompact: false)
        XCTAssertEqual(saved.columnCount, 3)
        XCTAssertEqual(saved.rowCount, 4)
    }

    func testRowCountClampsAndPersists() {
        let layout = GridLayout(defaults: defaults)
        layout.setRowCount(8)
        XCTAssertEqual(layout.rowCount, 8)
        XCTAssertEqual(layout.cellCount, layout.columnCount * 8)
        layout.setRowCount(1)
        XCTAssertEqual(layout.rowCount, GridLayout.defaultRows)
        let reopened = GridLayout(defaults: defaults)
        XCTAssertEqual(reopened.rowCount, GridLayout.defaultRows)
    }
}
