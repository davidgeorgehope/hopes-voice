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
}
