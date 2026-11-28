import Foundation

/// Part of speech for Fitzgerald-key coloring. Colors are our own fills on our own cells.
enum WordClass: String, CaseIterable, Codable, Sendable {
    case pronoun      // people and pronouns
    case verb         // actions
    case adjective    // describing words
    case noun         // things
    case social       // greetings, manners, yes/no
    case question     // what, where, who
    case preposition  // in, on, up, down
    case negation     // not, don't, stop
    case misc

    var title: String {
        switch self {
        case .pronoun: "People / pronoun"
        case .verb: "Action (verb)"
        case .adjective: "Describing"
        case .noun: "Thing (noun)"
        case .social: "Social"
        case .question: "Question"
        case .preposition: "Little word"
        case .negation: "No / not"
        case .misc: "Other"
        }
    }

    /// Default fills, `RRGGBB`. The first five match `docs/IMPORT_FORMAT.md`.
    var defaultHex: String {
        switch self {
        case .noun: "FFD966"
        case .verb: "93C47D"
        case .adjective: "6FA8DC"
        case .pronoun: "FFE599"
        case .social: "F4CCCC"
        case .question: "B4A7D6"
        case .preposition: "D9D2E9"
        case .negation: "EA9999"
        case .misc: "FFFFFF"
        }
    }

    /// Accepts our names and common synonyms (`adj`, `people`, `wh`, ...).
    init?(importName raw: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "pronoun", "people", "person", "name": self = .pronoun
        case "verb", "action": self = .verb
        case "adjective", "adj", "adverb", "describe", "describing": self = .adjective
        case "noun", "thing", "place": self = .noun
        case "social", "interjection", "greeting", "expression": self = .social
        case "question", "wh": self = .question
        case "preposition", "prep", "conjunction", "determiner", "article": self = .preposition
        case "negation", "negative", "not": self = .negation
        case "misc", "other": self = .misc
        default: return nil
        }
    }

    /// Best guess for a word on the default board. Unknown words are things (nouns),
    /// which is what most fringe vocabulary is.
    static func guess(for word: String) -> WordClass {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let known = lexicon[key] { return known }
        if key.hasPrefix("i want") || key.hasPrefix("i need") { return .verb }
        return .noun
    }

    private static let lexicon: [String: WordClass] = {
        var map: [String: WordClass] = [:]
        func add(_ words: [String], _ cls: WordClass) { for w in words { map[w] = cls } }
        add(["i", "me", "my", "mine", "you", "your", "he", "she", "him", "her", "it", "we", "us",
             "they", "them", "mommy", "mom", "mama", "daddy", "dad", "papa", "teacher", "friend",
             "baby", "brother", "sister", "grandma", "grandpa", "nana"], .pronoun)
        add(["want", "go", "help", "eat", "drink", "play", "like", "see", "look", "open", "make",
             "get", "put", "turn", "come", "give", "do", "read", "show", "stop it", "sleep", "wash",
             "sit", "stand", "walk", "run", "jump", "listen", "watch", "feel", "have", "need",
             "love", "finish", "wait", "push", "pull", "throw", "catch", "draw", "sing", "dance",
             "tickle", "hug", "kiss", "swing", "climb", "ride", "say", "tell", "think", "know"], .verb)
        add(["more", "big", "little", "small", "hot", "cold", "happy", "sad", "mad", "angry",
             "good", "bad", "all done", "done", "fast", "slow", "loud", "quiet", "wet", "dry",
             "dirty", "clean", "hungry", "thirsty", "tired", "sick", "hurt", "scared", "silly",
             "same", "different", "again", "too", "very", "now", "later", "here", "there",
             "red", "blue", "green", "yellow", "orange", "purple", "pink", "black", "white"], .adjective)
        add(["yes", "please", "thank you", "thanks", "hi", "hello", "bye", "goodbye", "sorry",
             "okay", "ok", "uh oh", "wow", "excuse me", "my turn", "your turn"], .social)
        add(["what", "where", "who", "when", "why", "how", "which"], .question)
        add(["in", "on", "off", "up", "down", "out", "under", "over", "to", "with", "for",
             "and", "the", "a", "an", "of", "at", "from", "this", "that", "some"], .preposition)
        add(["no", "not", "don't", "stop", "can't", "won't", "never"], .negation)
        return map
    }()
}
