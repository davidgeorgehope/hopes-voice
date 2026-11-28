import XCTest
@testable import BestWishes

final class SpeechPlanTests: XCTestCase {
    private func card(_ word: String, slug: String? = nil) -> Card {
        Card(word: word, slug: slug ?? word.lowercased(), imageURL: "", audioURL: "")
    }

    func testTypedWordsBecomeOneSentence() {
        let cards = [card("", slug: "typed:i"), card("", slug: "typed:love"), card("", slug: "typed:dogs")]
        let plan = SpeechPlayer.speechPlan(cards, spokenTexts: ["I", "love", "dogs"])
        XCTAssertEqual(plan, [.utterance("I love dogs")])
    }

    func testRecordingsStaySeparateBetweenTypedText() {
        let want = card("want")
        let cards = [card("", slug: "typed:i"), want, card("", slug: "typed:pizza"), card("", slug: "typed:please")]
        let plan = SpeechPlayer.speechPlan(cards, spokenTexts: ["I", "want", "pizza", "please"])
        XCTAssertEqual(plan, [.utterance("I"), .recording(want), .utterance("pizza please")])
    }

    func testRewordedButtonUsesItsNewWords() {
        let juice = card("juice")
        let plan = SpeechPlayer.speechPlan([juice], spokenTexts: ["apple juice"])
        XCTAssertEqual(plan, [.utterance("apple juice")])
    }

    func testNoTextsMeansRecordings() {
        let a = card("go"), b = card("stop")
        XCTAssertEqual(SpeechPlayer.speechPlan([a, b], spokenTexts: nil), [.recording(a), .recording(b)])
    }
}
