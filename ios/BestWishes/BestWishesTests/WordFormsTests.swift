import XCTest
@testable import BestWishes

final class WordFormsTests: XCTestCase {
    func testThingsGetPlurals() {
        XCTAssertEqual(WordForms.forms(for: "car", as: .noun), ["car", "cars"])
        XCTAssertEqual(WordForms.forms(for: "box", as: .noun), ["box", "boxes"])
        XCTAssertEqual(WordForms.forms(for: "puppy", as: .noun), ["puppy", "puppies"])
        XCTAssertEqual(WordForms.forms(for: "toy", as: .noun), ["toy", "toys"])
        XCTAssertEqual(WordForms.forms(for: "child", as: .noun), ["child", "children"])
        XCTAssertEqual(WordForms.forms(for: "sheep", as: .noun), ["sheep"], "same form is not offered twice")
    }

    func testActionsGetTenses() {
        XCTAssertEqual(WordForms.forms(for: "go", as: .verb), ["go", "goes", "going", "went", "gone"])
        XCTAssertEqual(WordForms.forms(for: "eat", as: .verb), ["eat", "eats", "eating", "ate", "eaten"])
        XCTAssertEqual(WordForms.forms(for: "stop", as: .verb), ["stop", "stops", "stopping", "stopped"])
        XCTAssertEqual(WordForms.forms(for: "like", as: .verb), ["like", "likes", "liking", "liked"])
        XCTAssertEqual(WordForms.forms(for: "play", as: .verb), ["play", "plays", "playing", "played"])
        XCTAssertEqual(WordForms.forms(for: "cry", as: .verb), ["cry", "cries", "crying", "cried"])
        XCTAssertEqual(WordForms.forms(for: "help", as: .verb), ["help", "helps", "helping", "helped"])
        XCTAssertEqual(WordForms.forms(for: "want", as: .verb), ["want", "wants", "wanting", "wanted"])
    }

    func testDescribingWordsGetComparisons() {
        XCTAssertEqual(WordForms.forms(for: "big", as: .adjective), ["big", "bigger", "biggest"])
        XCTAssertEqual(WordForms.forms(for: "happy", as: .adjective), ["happy", "happier", "happiest"])
        XCTAssertEqual(WordForms.forms(for: "good", as: .adjective), ["good", "better", "best"])
        XCTAssertEqual(WordForms.forms(for: "nice", as: .adjective), ["nice", "nicer", "nicest"])
        XCTAssertEqual(WordForms.forms(for: "beautiful", as: .adjective), ["beautiful"])
    }

    func testPronounsOfferTheirFamily() {
        XCTAssertEqual(WordForms.forms(for: "I"), ["I", "me", "my", "mine", "myself"])
        XCTAssertEqual(WordForms.forms(for: "she"), ["she", "her", "hers", "herself"])
        XCTAssertEqual(WordForms.forms(for: "them").first, "them")
    }

    func testBaseKeepsItsSpellingAndPhrasesAreLeftAlone() {
        XCTAssertEqual(WordForms.forms(for: "Dog", as: .noun), ["Dog", "dogs"])
        XCTAssertEqual(WordForms.forms(for: "ice cream", as: .noun), ["ice cream"])
        XCTAssertEqual(WordForms.forms(for: "hello", as: .social), ["hello"])
    }

    @MainActor
    func testPickedFormGoesOnTheMessageBar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-forms-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CardStore(api: APIClient(baseURL: APIClient.unreachableBaseURL), cache: AssetCache(root: root), player: SpeechPlayer())
        store.messageBar.speakOnTap = false
        let go = Card(word: "go", slug: "go", imageURL: "", audioURL: "")
        store.seedLocalBoard(cards: [go], folders: [])

        XCTAssertTrue(store.wordForms(for: go).contains("went"))
        store.tapForm(go, form: "went")
        store.tapForm(go, form: "go")

        XCTAssertEqual(store.strip.chips.map { store.chipLabel($0) }, ["went", "go"])
        XCTAssertEqual(store.strip.chips.map(\.text), ["went", nil])
        XCTAssertEqual(store.strip.slugs, ["go", "go"], "the chip keeps the button's picture")
    }
}
