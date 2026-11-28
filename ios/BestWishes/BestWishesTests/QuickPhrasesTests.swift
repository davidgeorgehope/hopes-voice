import XCTest
@testable import BestWishes

final class QuickPhrasesTests: XCTestCase {
    func testAddPutsNewestFirstAndSkipsRepeatsAndBlanks() {
        var phrases = QuickPhrases(phrases: ["Yes"])
        XCTAssertTrue(phrases.add("  I   want   juice "))
        XCTAssertFalse(phrases.add("i want JUICE"))
        XCTAssertFalse(phrases.add("   "))
        XCTAssertEqual(phrases.phrases, ["I want juice", "Yes"])
        phrases.remove("Yes")
        XCTAssertEqual(phrases.phrases, ["I want juice"])
    }

    func testPhrasesAreSavedPerProfileAndNewProfilesGetStarters() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = AssetCache(root: root)
        XCTAssertEqual(cache.loadQuickPhrases(for: .child1), .starters)
        var mine = QuickPhrases.starters
        mine.add("Let's go to the park")
        cache.saveQuickPhrases(mine, for: .child1)
        XCTAssertEqual(cache.loadQuickPhrases(for: .child1).phrases.first, "Let's go to the park")
        XCTAssertEqual(cache.loadQuickPhrases(for: .child2), .starters)
    }

    func testAPhraseChipSpeaksAsOneSentenceWithTypedWordsAround() {
        let phrase = Card(word: "", slug: CardStore.phraseSlugPrefix + "i need help", imageURL: "", audioURL: "")
        let typed = Card(word: "", slug: CardStore.typedSlugPrefix + "now", imageURL: "", audioURL: "")
        XCTAssertTrue(CardStore.isTextChip(phrase.slug))
        XCTAssertEqual(SpeechPlayer.speechPlan([phrase, typed], spokenTexts: ["I need help", "now"]), [.utterance("I need help now")])
    }
}
