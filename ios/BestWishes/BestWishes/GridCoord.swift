import Foundation
import SwiftUI

/// A stable cell on a fixed AAC grid. Row and column are 0-based, top-left origin.
struct GridCoord: Hashable, Codable, Sendable {
    var row: Int
    var col: Int

    func isInside(rows: Int, columns: Int) -> Bool {
        row >= 0 && col >= 0 && row < rows && col < columns
    }

    static func rowMajor(index: Int, columns: Int) -> GridCoord {
        let columns = max(columns, 1)
        return GridCoord(row: index / columns, col: index % columns)
    }

    func index(columns: Int) -> Int {
        row * max(columns, 1) + col
    }
}

/// One cell in the fixed board grid. Empty cells keep their position so buttons never slide.
enum BoardSlot: Identifiable, Hashable {
    case empty(GridCoord)
    /// A hidden item still owns this coordinate so Unhide returns to the same cell.
    case hidden(BoardItem, GridCoord)
    case item(BoardItem, GridCoord)

    var id: String {
        switch self {
        case .empty(let coord):
            return "empty-\(coord.row)-\(coord.col)"
        case .hidden(let item, _):
            return "hidden-\(item.id)"
        case .item(let item, _):
            return item.id
        }
    }

    var coord: GridCoord {
        switch self {
        case .empty(let coord), .hidden(_, let coord), .item(_, let coord):
            return coord
        }
    }

    var item: BoardItem? {
        switch self {
        case .empty:
            return nil
        case .hidden(let item, _), .item(let item, _):
            return item
        }
    }

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    var isHidden: Bool {
        if case .hidden = self { return true }
        return false
    }
}

/// Per-button colors. Stored on device as an overlay; not copied from any commercial AAC set.
struct CellStyle: Hashable, Codable, Sendable {
    var backgroundHex: String
    var borderHex: String

    static let `default` = CellStyle(backgroundHex: "FCFCF7", borderHex: "1C1A17")
}

enum ButtonKind: String, Codable, CaseIterable, Sendable {
    case word
    case folder
}
