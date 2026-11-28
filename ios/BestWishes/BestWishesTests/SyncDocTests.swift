import XCTest
@testable import BestWishes

final class SyncDocTests: XCTestCase {
    private func doc(labels: [String: String] = [:], hidden: [String] = [], images: [String: String] = [:]) -> SyncDoc {
        var d = SyncDoc()
        d.overlays.labels = labels
        d.overlays.hidden = hidden
        d.images = images
        return d
    }

    func testRemoteOnlyChangeWins() {
        let base = doc(labels: ["a": "one"])
        let merged = SyncDoc.merge(base: base, local: base, remote: doc(labels: ["a": "two"]))
        XCTAssertEqual(merged.overlays.labels, ["a": "two"])
    }

    func testLocalOnlyChangeIsKept() {
        let base = doc(labels: ["a": "one"])
        let merged = SyncDoc.merge(base: base, local: doc(labels: ["a": "mine"]), remote: base)
        XCTAssertEqual(merged.overlays.labels, ["a": "mine"])
    }

    func testEditsToDifferentKeysBothSurvive() {
        let base = doc(labels: ["a": "one", "b": "two"])
        let merged = SyncDoc.merge(
            base: base,
            local: doc(labels: ["a": "mine", "b": "two"]),
            remote: doc(labels: ["a": "one", "b": "theirs"])
        )
        XCTAssertEqual(merged.overlays.labels, ["a": "mine", "b": "theirs"])
    }

    func testSameKeyConflictLocalWins() {
        let base = doc(labels: ["a": "one"])
        let merged = SyncDoc.merge(base: base, local: doc(labels: ["a": "mine"]), remote: doc(labels: ["a": "theirs"]))
        XCTAssertEqual(merged.overlays.labels["a"], "mine")
    }

    func testRemoteDeleteRemovesKeyUnlessLocalChangedIt() {
        let base = doc(labels: ["a": "one", "b": "two"])
        let merged = SyncDoc.merge(base: base, local: base, remote: doc(labels: ["b": "two"]))
        XCTAssertEqual(merged.overlays.labels, ["b": "two"])
    }

    func testHiddenIsMergedAsASet() {
        let base = doc(hidden: ["x", "y"])
        let merged = SyncDoc.merge(
            base: base,
            local: doc(hidden: ["x", "y", "mine"]),
            remote: doc(hidden: ["y", "theirs"])
        )
        XCTAssertEqual(merged.overlays.hidden, ["mine", "theirs", "y"])
    }

    func testPositionsMergePerCell() {
        var base = SyncDoc(), local = SyncDoc(), remote = SyncDoc()
        base.overlays.positions = ["": ["a": GridCoord(row: 0, col: 0), "b": GridCoord(row: 0, col: 1)]]
        local.overlays.positions = ["": ["a": GridCoord(row: 2, col: 2), "b": GridCoord(row: 0, col: 1)]]
        remote.overlays.positions = ["": ["a": GridCoord(row: 0, col: 0), "b": GridCoord(row: 3, col: 3)]]
        let merged = SyncDoc.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(merged.overlays.positions[""]?["a"], GridCoord(row: 2, col: 2))
        XCTAssertEqual(merged.overlays.positions[""]?["b"], GridCoord(row: 3, col: 3))
    }

    func testBoardRemoteWinsUnlessLocalChangedIt() {
        var base = SyncDoc(), local = SyncDoc(), remote = SyncDoc()
        base.board = .object(["v": .int(1)])
        local.board = base.board
        remote.board = .object(["v": .int(2)])
        XCTAssertEqual(SyncDoc.merge(base: base, local: local, remote: remote).board, remote.board)
        local.board = .object(["v": .int(3)])
        XCTAssertEqual(SyncDoc.merge(base: base, local: local, remote: remote).board, local.board)
    }

    func testIntegerValuedDoubleEqualsIntSoARoundTripIsNotAnEdit() {
        var a = SyncDoc(), b = SyncDoc()
        a.board = .object(["rate": .int(1)])
        b.board = .object(["rate": .double(1.0)])
        XCTAssertEqual(a, b)
        b.board = .object(["rate": .double(1.5)])
        XCTAssertNotEqual(a, b)
    }

    func testDecodesWhatTheServerSends() throws {
        let json = """
        {"format":"bestwishes.sync/v1","board":null,
         "overlays":{"hidden":["stop"],"order":{"":["a","b"]},"labels":{"more":"Again"},
          "positions":{"":{"more":{"row":1,"col":2}}},"speak":{},
          "styles":{"more":{"backgroundHex":"FFD0D0","borderHex":"1C1A17"}}},
         "images":{"more":"\(String(repeating: "a", count: 64))"}}
        """
        let decoded = try JSONDecoder().decode(SyncDoc.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.overlays.hidden, ["stop"])
        XCTAssertEqual(decoded.overlays.positions[""]?["more"], GridCoord(row: 1, col: 2))
        XCTAssertEqual(decoded.overlays.styles["more"]?.backgroundHex, "FFD0D0")
        let again = try JSONDecoder().decode(SyncDoc.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(again, decoded)
    }
}
