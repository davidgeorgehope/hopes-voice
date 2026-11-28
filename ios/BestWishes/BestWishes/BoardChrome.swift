import SwiftUI

private struct BoardChromeKey: EnvironmentKey {
    static let defaultValue = BoardChrome.make(
        horizontalSizeClass: .regular,
        availableWidth: 800,
        columnCount: 3
    )
}

extension EnvironmentValues {
    var boardChrome: BoardChrome {
        get { self[BoardChromeKey.self] }
        set { self[BoardChromeKey.self] = newValue }
    }
}

/// Size-class-aware measurements so the board, core row, and sentence bar fit the screen width.
struct BoardChrome: Equatable {
    let isCompact: Bool
    let availableWidth: CGFloat
    let columnCount: Int

    let gridSpacing: CGFloat
    let gridPadding: CGFloat
    let stripSpacing: CGFloat
    let stripPadding: CGFloat
    let stripVerticalPadding: CGFloat
    let stripHeight: CGFloat
    let stripIconSize: CGFloat
    let stripLabelSize: CGFloat
    let stripPlaceholderSize: CGFloat
    let stripChipSpacing: CGFloat
    let speakWidth: CGFloat
    let sideButtonWidth: CGFloat
    let minimumChipWellWidth: CGFloat
    let chipWidth: CGFloat
    let chipImageHeight: CGFloat
    let chipLabelHeight: CGFloat
    let coreSpacing: CGFloat
    let corePadding: CGFloat
    let coreCellWidth: CGFloat
    let coreImageHeight: CGFloat
    let coreLabelHeight: CGFloat
    let coreTitleSize: CGFloat
    let cellTitleSize: CGFloat
    let cellLabelMinHeight: CGFloat
    let highlightStroke: CGFloat

    var cellWidth: CGFloat { cellWidth(columns: columnCount) }

    /// Width of one board cell when `columns` cells share the board width. Cells are given
    /// exactly this width so a wide label or picture can never push the grid off-screen.
    func cellWidth(columns: Int) -> CGFloat {
        let columns = max(columns, 1)
        let inner = availableWidth - gridPadding * 2 - gridSpacing * CGFloat(columns - 1)
        return max((inner / CGFloat(columns)).rounded(.down), 1)
    }

    var coreRowHeight: CGFloat { coreImageHeight + coreLabelHeight }

    /// Shortest a board cell may get before the board scrolls vertically instead.
    var minimumCellHeight: CGFloat { isCompact ? 64 : 80 }

    /// Height of one cell when `rows` rows (plus padding and spacing) share `available`
    /// points, floored at `minimum`.
    static func fittedCellHeight(
        available: CGFloat,
        rows: Int,
        verticalPadding: CGFloat,
        spacing: CGFloat,
        minimum: CGFloat
    ) -> CGFloat {
        let rows = max(rows, 1)
        let inner = available - verticalPadding * 2 - spacing * CGFloat(rows - 1)
        let fitted = (inner / CGFloat(rows)).rounded(.down)
        return max(fitted, minimum)
    }

    /// Flattest a default-board button may get (height ÷ width) before we show fewer rows.
    static let minimumCellAspect: CGFloat = 0.55

    /// Default-board cell height on iPad. Fit `rows` rows to the height, but if that makes
    /// buttons flatter than `minimumCellAspect` (landscape, or many rows), show fewer whole
    /// rows on screen and let the rest scroll. Depends only on the screen and the Rows
    /// setting, never on how many buttons a folder has, so cells keep one size everywhere.
    static func shapedCellHeight(
        available: CGFloat,
        rows: Int,
        cellWidth: CGFloat,
        verticalPadding: CGFloat,
        spacing: CGFloat,
        minimum: CGFloat
    ) -> CGFloat {
        let fitted = fittedCellHeight(available: available, rows: rows, verticalPadding: verticalPadding, spacing: spacing, minimum: minimum)
        let flattest = (cellWidth * minimumCellAspect).rounded(.down)
        guard fitted < flattest else { return fitted }
        let inner = available - verticalPadding * 2
        let rowsThatFit = Int(((inner + spacing) / (flattest + spacing)).rounded(.down))
        guard rowsThatFit >= 1 else { return max(flattest, minimum) }
        let refit = fittedCellHeight(available: available, rows: min(rowsThatFit, max(rows, 1)), verticalPadding: verticalPadding, spacing: spacing, minimum: minimum)
        return max(refit, flattest)
    }

    var chipHeight: CGFloat { chipImageHeight + chipLabelHeight }

    var gridItems: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: gridSpacing),
            count: columnCount
        )
    }

    /// Speak + Back + Clear + paddings + a usable chip well must fit `availableWidth`.
    var sentenceStripWidth: CGFloat {
        stripPadding * 2
            + speakWidth
            + sideButtonWidth * 2
            + stripSpacing * 3
            + minimumChipWellWidth
    }

    var coreRowWidth: CGFloat {
        corePadding * 2 + coreSpacing * 5 + coreCellWidth * 6
    }

    var boardRowWidth: CGFloat {
        gridPadding * 2 + gridSpacing * CGFloat(max(columnCount - 1, 0)) + cellWidth * CGFloat(columnCount)
    }

    static func make(
        horizontalSizeClass: UserInterfaceSizeClass?,
        availableWidth: CGFloat,
        columnCount: Int,
        availableHeight: CGFloat = 1_000
    ) -> BoardChrome {
        let width = max(availableWidth, 1)
        let compact = horizontalSizeClass == .compact || width < 600
        // A short iPad screen (iPad mini in landscape) gets a slimmer message bar and core
        // row so the board keeps most of the height. Widths stay iPad-sized.
        let short = !compact && availableHeight < 900
        let columns = max(columnCount, 1)

        let gridPadding: CGFloat = compact ? 10 : 24
        let gridSpacing: CGFloat = compact ? 8 : 22
        let highlightStroke: CGFloat = compact ? 5 : 8

        let stripPadding: CGFloat = compact ? 10 : 20
        let stripSpacing: CGFloat = compact ? 6 : 14
        let speakWidth: CGFloat = compact ? 64 : 108
        let sideButtonWidth: CGFloat = compact ? 48 : 88
        let stripHeight: CGFloat = compact ? 72 : (short ? 84 : 116)
        let reserved = stripPadding * 2 + speakWidth + sideButtonWidth * 2 + stripSpacing * 3
        let leftover = max(width - reserved, 0)
        let minimumChipWellWidth = max(leftover, compact ? 140 : 180)
        let chipWidth: CGFloat = compact ? 56 : 100
        let chipImageHeight: CGFloat = compact ? 48 : (short ? 46 : 76)
        let chipLabelHeight: CGFloat = compact ? 24 : (short ? 24 : 32)

        let corePadding: CGFloat = compact ? 10 : 20
        let coreSpacing: CGFloat = compact ? 6 : 10
        let coreInner = width - corePadding * 2 - coreSpacing * 5
        let coreCellWidth = max((coreInner / 6).rounded(.down), 36)
        let coreImageHeight: CGFloat = compact ? 48 : (short ? 52 : 92)
        let coreLabelHeight: CGFloat = compact ? 28 : (short ? 32 : 44)

        return BoardChrome(
            isCompact: compact,
            availableWidth: width,
            columnCount: columns,
            gridSpacing: gridSpacing,
            gridPadding: gridPadding,
            stripSpacing: stripSpacing,
            stripPadding: stripPadding,
            stripVerticalPadding: compact || short ? 8 : 12,
            stripHeight: stripHeight,
            stripIconSize: compact ? 18 : 28,
            stripLabelSize: compact ? 12 : 18,
            stripPlaceholderSize: compact ? 15 : 22,
            stripChipSpacing: compact ? 8 : 12,
            speakWidth: speakWidth,
            sideButtonWidth: sideButtonWidth,
            minimumChipWellWidth: minimumChipWellWidth,
            chipWidth: chipWidth,
            chipImageHeight: chipImageHeight,
            chipLabelHeight: chipLabelHeight,
            coreSpacing: coreSpacing,
            corePadding: corePadding,
            coreCellWidth: coreCellWidth,
            coreImageHeight: coreImageHeight,
            coreLabelHeight: coreLabelHeight,
            coreTitleSize: compact ? 13 : 22,
            cellTitleSize: compact ? 16 : 24,
            cellLabelMinHeight: compact ? 32 : 46,
            highlightStroke: highlightStroke
        )
    }
}
