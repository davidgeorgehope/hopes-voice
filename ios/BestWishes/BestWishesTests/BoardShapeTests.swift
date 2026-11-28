import XCTest
@testable import BestWishes

final class BoardShapeTests: XCTestCase {
    private func height(available: CGFloat, rows: Int, width: CGFloat) -> CGFloat {
        BoardChrome.shapedCellHeight(available: available, rows: rows, cellWidth: width, verticalPadding: 14, spacing: 22, minimum: 80)
    }

    func testRoomyScreenFitsTheRowsSetting() {
        // 4 rows in 800 pt: (800 - 28 - 66) / 4 = 176, taller than 0.62 × 162.
        XCTAssertEqual(height(available: 800, rows: 4, width: 162), 176)
    }

    func testTooManyRowsShowFewerWholeRowsInstead() {
        // 6 rows in 700 pt would be 93 pt (flatter than 100). 5 rows fit at 116 pt.
        let h = height(available: 700, rows: 6, width: 162)
        XCTAssertEqual(h, 116)
        XCTAssertGreaterThanOrEqual(h / 162, BoardChrome.minimumCellAspect)
    }

    func testLandscapeKeepsButtonsFromGoingFlat() {
        // Wide cells, short board: 6 rows would be 80-pt strips. Show 3 rows of 176 pt.
        let h = height(available: 600, rows: 6, width: 255)
        XCTAssertEqual(h, 176)
        XCTAssertGreaterThanOrEqual(h / 255, BoardChrome.minimumCellAspect)
    }

    func testTinyBoardStillGivesOneUsableRow() {
        XCTAssertEqual(height(available: 120, rows: 6, width: 255), 158)
    }
}
