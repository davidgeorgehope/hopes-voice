import Foundation

/// One profile's syncable state: the imported board (optional), the caregiver overlays, and
/// content hashes of caregiver photos. Wire format `bestwishes.sync/v1` (see docs/SYNC.md).
nonisolated struct SyncDoc: Codable, Equatable, Sendable {
    static let format = "bestwishes.sync/v1"

    var format: String = SyncDoc.format
    var board: JSONValue?
    var overlays = Overlays()
    /// Cache slug → sha256 of the caregiver photo (PNG bytes).
    var images: [String: String] = [:]

    struct Overlays: Codable, Equatable, Sendable {
        var hidden: [String] = []
        var order: [String: [String]] = [:]
        var labels: [String: String] = [:]
        var positions: [String: [String: GridCoord]] = [:]
        var speak: [String: String] = [:]
        var styles: [String: CellStyle] = [:]
    }

    static let empty = SyncDoc()

    static func == (lhs: SyncDoc, rhs: SyncDoc) -> Bool {
        lhs.overlays == rhs.overlays && lhs.images == rhs.images
            && lhs.board.map(normalised) == rhs.board.map(normalised)
    }

    /// Integer-valued doubles equal ints, so a round trip through the server never looks like an edit.
    static func normalised(_ value: JSONValue) -> JSONValue {
        switch value {
        case .double(let d) where d.rounded() == d && abs(d) < 1e15: return .int(Int(d))
        case .array(let items): return .array(items.map(normalised))
        case .object(let items): return .object(items.mapValues(normalised))
        default: return value
        }
    }

    // MARK: Three-way merge

    /// Merge two devices' edits relative to a common ancestor. Anything only one side changed
    /// is kept; when both changed the same entry, `local` wins. Nothing is ever dropped silently
    /// except by an explicit local delete.
    static func merge(base: SyncDoc, local: SyncDoc, remote: SyncDoc) -> SyncDoc {
        var out = SyncDoc()
        // The board is replaced as a whole: remote wins unless this device also changed it.
        if local.board != nil, local.board.map(normalised) != base.board.map(normalised) {
            out.board = local.board
        } else {
            out.board = remote.board ?? local.board
        }
        out.overlays.hidden = mergeSet(base.overlays.hidden, local.overlays.hidden, remote.overlays.hidden)
        out.overlays.order = mergeMap(base.overlays.order, local.overlays.order, remote.overlays.order)
        out.overlays.labels = mergeMap(base.overlays.labels, local.overlays.labels, remote.overlays.labels)
        out.overlays.speak = mergeMap(base.overlays.speak, local.overlays.speak, remote.overlays.speak)
        out.overlays.styles = mergeMap(base.overlays.styles, local.overlays.styles, remote.overlays.styles)
        out.images = mergeMap(base.images, local.images, remote.images)
        var positions: [String: [String: GridCoord]] = [:]
        let keys = Set(base.overlays.positions.keys).union(local.overlays.positions.keys).union(remote.overlays.positions.keys)
        for key in keys {
            let merged = mergeMap(
                base.overlays.positions[key] ?? [:],
                local.overlays.positions[key] ?? [:],
                remote.overlays.positions[key] ?? [:]
            )
            if !merged.isEmpty { positions[key] = merged }
        }
        out.overlays.positions = positions
        return out
    }

    static func mergeMap<V: Equatable>(_ base: [String: V], _ local: [String: V], _ remote: [String: V]) -> [String: V] {
        var out: [String: V] = [:]
        for key in Set(base.keys).union(local.keys).union(remote.keys) {
            let value = local[key] != base[key] ? local[key] : remote[key]
            if let value { out[key] = value }
        }
        return out
    }

    static func mergeSet(_ base: [String], _ local: [String], _ remote: [String]) -> [String] {
        let b = Set(base), l = Set(local), r = Set(remote)
        var out: [String] = []
        for item in b.union(l).union(r) {
            let present = (l.contains(item) != b.contains(item)) ? l.contains(item) : r.contains(item)
            if present { out.append(item) }
        }
        return out.sorted()
    }
}
