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

    func testValuesOutsideTwoThreeFourDoNotProduceFifthDensity() {
        let layout = GridLayout(defaults: defaults)

        for invalid in [0, 1, 5, 6, -1, 99] {
            layout.setColumnCount(invalid)

            XCTAssertTrue(
                GridLayout.allowedCounts.contains(layout.columnCount),
                "\(invalid) produced \(layout.columnCount)"
            )
            XCTAssertFalse(GridLayout.allowedCounts.contains(invalid))
            XCTAssertEqual(layout.columnCount, GridLayout.defaultCount)
            XCTAssertEqual(layout.gridItems.count, layout.columnCount)
            XCTAssertNotEqual(layout.gridItems.count, invalid)
        }

        defaults.set(1, forKey: GridLayout.defaultsKey)
        let fromStored = GridLayout(defaults: defaults)
        XCTAssertTrue(GridLayout.allowedCounts.contains(fromStored.columnCount))
        XCTAssertEqual(fromStored.gridItems.count, fromStored.columnCount)
        XCTAssertNotEqual(fromStored.columnCount, 1)
        XCTAssertNotEqual(fromStored.columnCount, 5)
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

    func testLaunchArgOutsideRangeDoesNotProduceFifthDensity() {
        let layout = GridLayout(defaults: defaults)
        layout.applyLaunchArguments(["-GridColumns", "5"])
        XCTAssertEqual(layout.columnCount, 3)
        XCTAssertEqual(layout.gridItems.count, 3)
    }
}
