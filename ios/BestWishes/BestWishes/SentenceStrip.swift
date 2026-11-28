import Foundation

/// One chip on the sentence strip. Duplicate words are allowed; `id` distinguishes them.
struct SentenceChip: Identifiable, Equatable, Sendable {
    let id: UUID
    let card: Card
    /// A word form picked on long-press ("cats", "went"). Nil means the button's own word.
    let text: String?

    init(card: Card, text: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.card = card
        self.text = text
    }
}

/// Ordered AAC message window. Speak plays `cards` (and their cached MP3s) in this order.
struct SentenceStrip: Equatable, Sendable {
    private(set) var chips: [SentenceChip] = []

    var cards: [Card] { chips.map(\.card) }
    var slugs: [String] { chips.map(\.card.slug) }
    var isEmpty: Bool { chips.isEmpty }

    mutating func append(_ card: Card, text: String? = nil) {
        chips.append(SentenceChip(card: card, text: text))
    }

    mutating func backspace() {
        guard !chips.isEmpty else { return }
        chips.removeLast()
    }

    mutating func clear() {
        chips.removeAll()
    }

    /// Cached MP3 paths Speak will request, in strip order.
    func cachedAudioURLs(using cache: AssetCache) -> [URL] {
        cards.map { cache.audioURL(for: $0.slug) }
    }
}
