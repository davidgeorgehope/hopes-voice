import Foundation

/// Word prediction for the keyboard page. Local only.
///
/// While a word is half typed, it offers completions: words this child has typed before
/// (most used first), then words on their board, then a built-in list of common words.
/// After a space it offers likely next words from the child's own word pairs, then common
/// words. "I" is always capitalized.
struct WordPredictor {
    var boardWords: [String] = []
    var history = KeyboardHistory()

    static let commonWords: [String] = [
        "I", "you", "it", "is", "want", "more", "go", "stop", "help", "like", "not", "the", "a",
        "to", "and", "my", "me", "that", "this", "what", "where", "who", "when", "why", "can",
        "do", "don't", "have", "get", "make", "play", "eat", "drink", "look", "see", "come",
        "put", "turn", "open", "all", "done", "finished", "again", "different", "here", "there",
        "in", "on", "off", "up", "down", "out", "with", "for", "of", "at", "please", "thank",
        "thanks", "yes", "no", "hello", "hi", "bye", "good", "bad", "happy", "sad", "mad",
        "tired", "hungry", "thirsty", "hurt", "sick", "hot", "cold", "big", "little", "fast",
        "slow", "now", "later", "today", "tomorrow", "mom", "mommy", "dad", "daddy", "friend",
        "teacher", "home", "school", "outside", "bathroom", "potty", "water", "juice", "milk",
        "snack", "food", "toy", "book", "music", "tv", "iPad", "car", "bed", "love", "feel",
        "need", "think", "know", "say", "tell", "give", "take", "read", "watch", "listen",
        "wait", "walk", "run", "sit", "sleep", "wash", "brush", "my turn", "your turn",
        "we", "they", "he", "she", "him", "her", "us", "them", "your", "our", "some", "one",
        "two", "three", "red", "blue", "green", "yellow", "dog", "cat", "ball", "bubbles",
        "swing", "park", "shoes", "coat", "hug", "kiss", "sorry", "okay", "fun", "funny",
        "scared", "excited", "because", "but", "or", "if", "was", "are", "am", "will", "did",
    ].filter { !$0.contains(" ") }

    /// Up to `limit` suggestions for what's typed so far.
    func suggestions(for text: String, limit: Int = 4) -> [String] {
        let endsWord = text.isEmpty || text.last == " "
        var words = text.split(whereSeparator: { $0 == " " }).map(String.init)
        var out: [String] = []
        func add(_ word: String) {
            let shown = Self.shown(word)
            guard !shown.isEmpty, out.count < limit,
                  !out.contains(where: { $0.caseInsensitiveCompare(shown) == .orderedSame }) else { return }
            out.append(shown)
        }
        if endsWord {
            if let last = words.last {
                for next in history.nextWords(after: last) { add(next) }
            }
            for word in history.mostUsed() { add(word) }
            for word in Self.commonWords { add(word) }
            return out
        }
        let prefix = (words.popLast() ?? "").lowercased()
        func matches(_ word: String) -> Bool {
            let lower = word.lowercased()
            return lower.hasPrefix(prefix) && lower != prefix
        }
        for word in history.mostUsed() where matches(word) { add(word) }
        let board = boardWords.filter { !$0.contains(" ") && matches($0) }
            .sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
        for word in board { add(word) }
        for word in Self.commonWords where matches(word) { add(word) }
        return out
    }

    /// The typed text with its last, half-typed word replaced by `word`, plus a space.
    static func accept(_ word: String, into text: String) -> String {
        var base = text
        if let last = base.last, last != " " {
            while let c = base.last, c != " " { base.removeLast() }
        }
        return base + word + " "
    }

    static func shown(_ word: String) -> String {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased() == "i" ? "I" : trimmed
    }
}

/// What the child has typed: how often each word was used and which word followed which.
struct KeyboardHistory: Codable, Equatable {
    var counts: [String: Int] = [:]
    var pairs: [String: [String: Int]] = [:]

    mutating func learn(_ sentence: String) {
        let words = sentence.split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map { WordPredictor.shown(String($0)).lowercased() }
            .filter { !$0.isEmpty }
        for word in words { counts[word, default: 0] += 1 }
        for (a, b) in zip(words, words.dropFirst()) { pairs[a, default: [:]][b, default: 0] += 1 }
    }

    func mostUsed() -> [String] {
        counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    func nextWords(after word: String) -> [String] {
        (pairs[word.lowercased()] ?? [:])
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
    }
}
