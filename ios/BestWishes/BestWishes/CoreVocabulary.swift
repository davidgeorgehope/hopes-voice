import Foundation

/// Proloquo-style core strip. Words are resolved against **server** cards
/// (same `Card` records the grid uses). Art and MP3s come from the on-device
/// cache of server assets — nothing is bundled locally.
enum CoreVocabulary {
    struct Entry: Equatable, Sendable {
        let word: String
        let slug: String
    }

    /// On-screen order. Slugs match server slugify (lowercase alphanumerics).
    static let ordered: [Entry] = [
        Entry(word: "I", slug: "i"),
        Entry(word: "want", slug: "want"),
        Entry(word: "more", slug: "more"),
        Entry(word: "help", slug: "help"),
        Entry(word: "stop", slug: "stop"),
        Entry(word: "go", slug: "go"),
    ]

    static let words: [String] = ordered.map(\.word)
    static let slugs: [String] = ordered.map(\.slug)

    static func matches(_ entry: Entry, _ card: Card) -> Bool {
        card.slug.caseInsensitiveCompare(entry.slug) == .orderedSame
            || card.word.caseInsensitiveCompare(entry.word) == .orderedSame
    }

    static func matches(_ card: Card) -> Bool {
        ordered.contains { matches($0, card) }
    }

    /// Prefer an exact slug hit, then a case-insensitive word hit.
    static func resolve(_ entry: Entry, from cards: [Card]) -> Card? {
        if let bySlug = cards.first(where: { $0.slug.caseInsensitiveCompare(entry.slug) == .orderedSame }) {
            return bySlug
        }
        return cards.first(where: { $0.word.caseInsensitiveCompare(entry.word) == .orderedSame })
    }

    static func resolved(from cards: [Card]) -> [Card] {
        ordered.compactMap { resolve($0, from: cards) }
    }

    static func missing(from cards: [Card]) -> [Entry] {
        ordered.filter { resolve($0, from: cards) == nil }
    }
}
