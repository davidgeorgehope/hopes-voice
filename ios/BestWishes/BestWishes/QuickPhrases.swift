import Foundation

/// Saved sentences a child can say with one tap. Kept per profile, newest first.
struct QuickPhrases: Codable, Equatable, Sendable {
    var phrases: [String]

    /// What a new profile starts with: short, everyday, easy to change.
    static let starters = QuickPhrases(phrases: [
        "I need help",
        "I want more",
        "I'm all done",
        "Yes",
        "No",
        "Thank you",
        "I need a break",
        "I don't like that",
    ])

    /// Adds a phrase at the top. Blank text and repeats (any case) are ignored.
    @discardableResult
    mutating func add(_ text: String) -> Bool {
        let phrase = Self.clean(text)
        guard !phrase.isEmpty,
              !phrases.contains(where: { $0.caseInsensitiveCompare(phrase) == .orderedSame }) else { return false }
        phrases.insert(phrase, at: 0)
        return true
    }

    mutating func remove(_ phrase: String) {
        phrases.removeAll { $0 == phrase }
    }

    /// One space between words, no space at the ends.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
