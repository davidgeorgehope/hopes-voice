import Foundation

/// One chip on the sentence strip. Duplicate words are allowed; `id` distinguishes them.
struct SentenceChip: Identifiable, Equatable, Sendable {
    let id: UUID
    let card: Card

    init(card: Card, id: UUID = UUID()) {
        self.id = id
        self.card = card
    }
}

/// Ordered AAC message window. Speak plays `cards` (and their cached MP3s) in this order.
struct SentenceStrip: Equatable, Sendable {
    private(set) var chips: [SentenceChip] = []

    var cards: [Card] { chips.map(\.card) }
    var slugs: [String] { chips.map(\.card.slug) }
    var isEmpty: Bool { chips.isEmpty }

    mutating func append(_ card: Card) {
        chips.append(SentenceChip(card: card))
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
