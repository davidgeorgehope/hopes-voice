import SwiftUI
import XCTest
@testable import BestWishes

final class BoardChromeTests: XCTestCase {
    /// iPhone 16 Pro logical portrait width.
    private let iPhoneWidth: CGFloat = 393
    /// 11-inch iPad logical portrait width (approx).
    private let iPadWidth: CGFloat = 820

    func testFourColumnsFitIPhone16ProWidth() {
        let chrome = BoardChrome.make(
            horizontalSizeClass: .compact,
            availableWidth: iPhoneWidth,
            columnCount: 4
        )
        XCTAssertTrue(chrome.isCompact)
        XCTAssertLessThanOrEqual(chrome.boardRowWidth, iPhoneWidth)
        XCTAssertGreaterThan(chrome.cellWidth, 40)
    }

    func testThreeColumnsFitIPhoneAndIPadWidth() {
        let phone = BoardChrome.make(
            horizontalSizeClass: .compact,
            availableWidth: iPhoneWidth,
            columnCount: 3
        )
        XCTAssertLessThanOrEqual(phone.boardRowWidth, iPhoneWidth)

        let pad = BoardChrome.make(
            horizontalSizeClass: .regular,
            availableWidth: iPadWidth,
            columnCount: 4
        )
        XCTAssertFalse(pad.isCompact)
        XCTAssertLessThanOrEqual(pad.boardRowWidth, iPadWidth)
    }

    func testSentenceStripFitsIPhone16ProWidth() {
        let chrome = BoardChrome.make(
            horizontalSizeClass: .compact,
            availableWidth: iPhoneWidth,
            columnCount: 3
        )
        XCTAssertLessThanOrEqual(chrome.sentenceStripWidth, iPhoneWidth)
        XCTAssertGreaterThanOrEqual(chrome.minimumChipWellWidth, 140)
        XCTAssertGreaterThan(chrome.chipWidth, 0)
        XCTAssertLessThan(chrome.chipWidth, chrome.minimumChipWellWidth)
    }

    func testCoreRowSixCellsFitIPhone16ProWidth() {
        let chrome = BoardChrome.make(
            horizontalSizeClass: .compact,
            availableWidth: iPhoneWidth,
            columnCount: 3
        )
        XCTAssertLessThanOrEqual(chrome.coreRowWidth, iPhoneWidth)
        XCTAssertGreaterThan(chrome.coreCellWidth, 30)
        XCTAssertEqual(chrome.coreRowHeight, chrome.coreImageHeight + chrome.coreLabelHeight)
    }

    func testSentenceStripFitsIPadWidth() {
        let chrome = BoardChrome.make(
            horizontalSizeClass: .regular,
            availableWidth: iPadWidth,
            columnCount: 4
        )
        XCTAssertLessThanOrEqual(chrome.sentenceStripWidth, iPadWidth)
        XCTAssertLessThanOrEqual(chrome.coreRowWidth, iPadWidth)
    }

    /// iPhone SE, 16 Pro, and Pro Max portrait widths plus an iPad mini: rows fit the width.
    func testEveryRowFitsCommonPhoneAndPadWidths() {
        for width: CGFloat in [375, 393, 440, 744] {
            for columns in 2...8 {
                let chrome = BoardChrome.make(horizontalSizeClass: width < 600 ? .compact : .regular, availableWidth: width, columnCount: columns)
                XCTAssertLessThanOrEqual(chrome.boardRowWidth, width, "\(columns) columns at \(width)")
                XCTAssertLessThanOrEqual(chrome.coreRowWidth, width, "core row at \(width)")
                XCTAssertLessThanOrEqual(chrome.sentenceStripWidth, width, "message bar at \(width)")
            }
        }
    }

    func testFittedCellHeightSharesTheHeightAndHasAFloor() {
        // 4 rows in 500 pt with 15 pt padding top and bottom and 8 pt gaps.
        let h = BoardChrome.fittedCellHeight(available: 500, rows: 4, verticalPadding: 15, spacing: 8, minimum: 64)
        XCTAssertEqual(h, 111)
        XCTAssertLessThanOrEqual(h * 4 + 8 * 3 + 30, 500)
        // A short landscape phone board floors at the minimum and scrolls instead.
        XCTAssertEqual(BoardChrome.fittedCellHeight(available: 150, rows: 4, verticalPadding: 15, spacing: 8, minimum: 72), 72)
        XCTAssertEqual(BoardChrome.fittedCellHeight(available: 500, rows: 0, verticalPadding: 15, spacing: 8, minimum: 72), 470)
    }
}
