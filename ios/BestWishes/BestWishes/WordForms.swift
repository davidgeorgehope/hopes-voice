import Foundation

/// Grammar forms for a word, offered on long-press (like an AAC "word forms" popup):
/// plurals for things, tenses for actions, comparatives for describing words, and the
/// other cases of a pronoun. Rules plus a small irregular list; the base word comes first.
enum WordForms {
    static func forms(for word: String, as wordClass: WordClass? = nil) -> [String] {
        let base = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = base.lowercased()
        guard !lower.isEmpty, !lower.contains(" ") else { return [base] }
        let cls = wordClass ?? WordClass.guess(for: lower)
        var out: [String]
        if let set = pronouns[lower] {
            out = set
        } else {
            switch cls {
            case .noun: out = [lower, plural(lower)]
            case .verb: out = verbForms(lower)
            case .adjective: out = adjectiveForms(lower)
            default: out = [lower]
            }
        }
        // Keep the caregiver's own spelling and capitalisation for the base word ("I", names).
        out[0] = base
        var seen = Set<String>()
        return out.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: Things

    private static let irregularPlurals: [String: String] = [
        "child": "children", "man": "men", "woman": "women", "person": "people",
        "mouse": "mice", "foot": "feet", "tooth": "teeth", "goose": "geese",
        "sheep": "sheep", "fish": "fish", "deer": "deer", "leaf": "leaves",
        "knife": "knives", "wolf": "wolves", "shelf": "shelves", "potato": "potatoes",
        "tomato": "tomatoes", "baby": "babies", "puppy": "puppies", "ox": "oxen",
    ]

    static func plural(_ word: String) -> String {
        if let irregular = irregularPlurals[word] { return irregular }
        if word.hasSuffix("y"), let before = word.dropLast().last, !"aeiou".contains(before) {
            return word.dropLast() + "ies"
        }
        if ["s", "x", "z", "ch", "sh"].contains(where: word.hasSuffix) { return word + "es" }
        return word + "s"
    }

    // MARK: Actions

    /// base → (past, past participle)
    private static let irregularVerbs: [String: (String, String)] = [
        "be": ("was", "been"), "go": ("went", "gone"), "eat": ("ate", "eaten"),
        "drink": ("drank", "drunk"), "see": ("saw", "seen"), "come": ("came", "come"),
        "get": ("got", "got"), "give": ("gave", "given"), "have": ("had", "had"),
        "do": ("did", "done"), "make": ("made", "made"), "take": ("took", "taken"),
        "run": ("ran", "run"), "sit": ("sat", "sat"), "sleep": ("slept", "slept"),
        "read": ("read", "read"), "say": ("said", "said"), "tell": ("told", "told"),
        "find": ("found", "found"), "feel": ("felt", "felt"), "fall": ("fell", "fallen"),
        "hold": ("held", "held"), "swim": ("swam", "swum"), "sing": ("sang", "sung"),
        "ride": ("rode", "ridden"), "write": ("wrote", "written"), "draw": ("drew", "drawn"),
        "throw": ("threw", "thrown"), "break": ("broke", "broken"), "buy": ("bought", "bought"),
        "bring": ("brought", "brought"), "think": ("thought", "thought"), "know": ("knew", "known"),
        "put": ("put", "put"), "cut": ("cut", "cut"), "hurt": ("hurt", "hurt"),
        "stand": ("stood", "stood"), "wear": ("wore", "worn"), "win": ("won", "won"),
        "hide": ("hid", "hidden"), "blow": ("blew", "blown"), "build": ("built", "built"),
        "catch": ("caught", "caught"), "fly": ("flew", "flown"), "begin": ("began", "begun"),
        "lose": ("lost", "lost"), "meet": ("met", "met"), "pay": ("paid", "paid"),
        "send": ("sent", "sent"), "spend": ("spent", "spent"), "teach": ("taught", "taught"),
        "wake": ("woke", "woken"), "forget": ("forgot", "forgotten"), "shake": ("shook", "shaken"),
    ]
    private static let thirdPersonIrregular: [String: String] = ["be": "is", "have": "has", "do": "does", "go": "goes"]
    private static let ingIrregular: [String: String] = ["be": "being", "see": "seeing", "lie": "lying", "die": "dying", "tie": "tying"]

    static func verbForms(_ verb: String) -> [String] {
        let third = thirdPersonIrregular[verb] ?? sForm(verb)
        let ing = ingIrregular[verb] ?? ingForm(verb)
        if let (past, participle) = irregularVerbs[verb] {
            return [verb, third, ing, past, participle]
        }
        return [verb, third, ing, edForm(verb)]
    }

    private static func sForm(_ verb: String) -> String {
        if verb.hasSuffix("y"), let before = verb.dropLast().last, !"aeiou".contains(before) {
            return verb.dropLast() + "ies"
        }
        if ["s", "x", "z", "ch", "sh", "o"].contains(where: verb.hasSuffix) { return verb + "es" }
        return verb + "s"
    }

    /// One short vowel between two consonants at the end ("stop", "hug") doubles the consonant.
    private static func doublesFinalConsonant(_ word: String) -> Bool {
        let chars = Array(word)
        guard chars.count >= 3 && chars.count <= 4 else { return false }
        let vowels = Set("aeiou")
        let last = chars[chars.count - 1], mid = chars[chars.count - 2], first = chars[chars.count - 3]
        return !vowels.contains(last) && !"wxy".contains(last) && vowels.contains(mid) && !vowels.contains(first)
    }

    private static func ingForm(_ verb: String) -> String {
        if verb.hasSuffix("ie") { return verb.dropLast(2) + "ying" }
        if verb.hasSuffix("e"), !verb.hasSuffix("ee"), verb.count > 2 { return verb.dropLast() + "ing" }
        if doublesFinalConsonant(verb) { return verb + String(verb.last!) + "ing" }
        return verb + "ing"
    }

    private static func edForm(_ verb: String) -> String {
        if verb.hasSuffix("e") { return verb + "d" }
        if verb.hasSuffix("y"), let before = verb.dropLast().last, !"aeiou".contains(before) {
            return verb.dropLast() + "ied"
        }
        if doublesFinalConsonant(verb) { return verb + String(verb.last!) + "ed" }
        return verb + "ed"
    }

    // MARK: Describing words

    private static let irregularAdjectives: [String: (String, String)] = [
        "good": ("better", "best"), "bad": ("worse", "worst"), "far": ("farther", "farthest"),
        "little": ("littler", "littlest"), "many": ("more", "most"), "much": ("more", "most"),
    ]

    static func adjectiveForms(_ adjective: String) -> [String] {
        if let (more, most) = irregularAdjectives[adjective] { return [adjective, more, most] }
        // Long words ("beautiful") take "more" / "most" in speech; offer just the word.
        guard adjective.count <= 6 else { return [adjective] }
        if adjective.hasSuffix("e") { return [adjective, adjective + "r", adjective + "st"] }
        if adjective.hasSuffix("y"), let before = adjective.dropLast().last, !"aeiou".contains(before) {
            let stem = adjective.dropLast()
            return [adjective, stem + "ier", stem + "iest"]
        }
        if doublesFinalConsonant(adjective) {
            let doubled = adjective + String(adjective.last!)
            return [adjective, doubled + "er", doubled + "est"]
        }
        return [adjective, adjective + "er", adjective + "est"]
    }

    // MARK: People

    private static let pronouns: [String: [String]] = {
        let sets: [[String]] = [
            ["I", "me", "my", "mine", "myself"],
            ["you", "your", "yours", "yourself"],
            ["he", "him", "his", "himself"],
            ["she", "her", "hers", "herself"],
            ["it", "its", "itself"],
            ["we", "us", "our", "ours", "ourselves"],
            ["they", "them", "their", "theirs", "themselves"],
        ]
        var map: [String: [String]] = [:]
        for set in sets {
            for word in set {
                // Long-pressing "me" offers "me" first, then the rest of its family.
                map[word.lowercased()] = [word] + set.filter { $0 != word }
            }
        }
        return map
    }()
}
