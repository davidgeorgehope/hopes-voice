import Foundation

/// What the home screen shows on a board that isn't imported.
enum HomeLayout: String, Codable, CaseIterable, Sendable {
    /// The family's own buttons and folders.
    case myBoard
    /// A fixed grid of the most-used core words, then the family's folders.
    case coreWords
}

/// Core-word home: high-frequency words a child can combine into many sentences, always in
/// the same spots so motor memory builds. A word that already has a button uses it (picture and
/// recorded voice); the others are word tiles spoken with the device voice.
enum CoreWords {
    static let slugPrefix = "core:"

    /// Fixed order. Read in rows of six: people and wanting, then actions, describing words,
    /// little words, and questions.
    static let words: [String] = [
        "I", "you", "want", "more", "go", "stop",
        "help", "like", "not", "it", "that", "here",
        "my", "me", "can", "do", "get", "look",
        "eat", "drink", "play", "put", "turn", "open",
        "big", "little", "good", "bad", "all", "done",
        "in", "on", "up", "down", "what", "where",
    ]

    /// Home items for the core layout: one per core word, then `folders`.
    /// `existing` finds a visible button whose label matches (case-insensitive).
    static func items(existing: (String) -> Card?, folders: [BoardFolder]) -> [BoardItem] {
        let words = Self.words.map { word -> BoardItem in
            if let card = existing(word) { return .word(card) }
            return .word(Card(word: word, slug: slugPrefix + word.lowercased(), imageURL: "", audioURL: ""))
        }
        return words + folders.map { .folder($0) }
    }

    static func isCoreTile(_ card: Card) -> Bool { card.slug.hasPrefix(slugPrefix) }
}
