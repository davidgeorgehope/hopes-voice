import XCTest
@testable import BestWishes

final class WordPredictorTests: XCTestCase {
    func testCompletesFromBoardWordsThenCommonWords() {
        let p = WordPredictor(boardWords: ["water", "want", "Daddy"])
        let s = p.suggestions(for: "wa")
        XCTAssertEqual(Array(s.prefix(2)), ["want", "water"], "board words first, shorter first")
        XCTAssertTrue(s.contains("wait") || s.contains("walk"), "then common words: \(s)")
        XCTAssertFalse(s.contains("wa"))
        XCTAssertEqual(p.suggestions(for: "da").first, "Daddy", "board spelling kept")
    }

    func testWordsTheChildTypedComeFirst() {
        var history = KeyboardHistory()
        history.learn("I want waffles")
        history.learn("waffles please")
        let p = WordPredictor(boardWords: ["water", "want"], history: history)
        XCTAssertEqual(p.suggestions(for: "wa").first, "waffles")
    }

    func testAfterASpaceSuggestsWhatUsuallyComesNext() {
        var history = KeyboardHistory()
        history.learn("I want juice")
        history.learn("I want juice")
        history.learn("I want cookie")
        let p = WordPredictor(history: history)
        XCTAssertEqual(Array(p.suggestions(for: "i want ").prefix(2)), ["juice", "cookie"])
        XCTAssertEqual(p.suggestions(for: "").first, "I", "empty text suggests common starters, I capitalized")
    }

    func testAcceptReplacesTheHalfTypedWord() {
        XCTAssertEqual(WordPredictor.accept("want", into: "I wa"), "I want ")
        XCTAssertEqual(WordPredictor.accept("juice", into: "I want "), "I want juice ")
        XCTAssertEqual(WordPredictor.accept("I", into: "i"), "I ")
    }

    func testLimitAndNoDuplicates() {
        let p = WordPredictor(boardWords: ["help", "Help", "hello", "hi", "he", "her", "him"])
        let s = p.suggestions(for: "h", limit: 4)
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(Set(s.map { $0.lowercased() }).count, 4)
    }

    @MainActor
    func testTypedWordsGoOnTheBarAndAreLearned() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-kb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AssetCache(root: root)
        let store = CardStore(api: APIClient(baseURL: APIClient.unreachableBaseURL), cache: cache, player: SpeechPlayer())
        store.addTypedToMessageBar("i want pancakes ")
        XCTAssertEqual(store.strip.chips.map { store.chipLabel($0) }, ["I", "want", "pancakes"])
        XCTAssertTrue(store.strip.slugs.allSatisfy { $0.hasPrefix(CardStore.typedSlugPrefix) })
        XCTAssertEqual(store.keyboardPredictor().suggestions(for: "pa").first, "pancakes", "learned for next time")
        XCTAssertEqual(store.keyboardPredictor().suggestions(for: "want ").first, "pancakes")
    }
}
