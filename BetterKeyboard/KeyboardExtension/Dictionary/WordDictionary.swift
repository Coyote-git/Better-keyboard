import Foundation

/// Loads and queries a bundled word list for swipe decoding.
class WordDictionary {

    private var words: Set<String> = []
    private var wordsByFirstLast: [String: [String]] = [:]  // "t-e" → ["the", "there", ...]
    private var frequencyIndex: [String: Int] = [:]         // word → rank (0 = most common)
    /// Frequency-ordered word list (first = most common)
    private(set) var wordList: [String] = []

    /// Words that should always be capitalized (proper nouns, names).
    static let properNouns: Set<String> = [
        // Names — unambiguous only (removed: ben, bob, carol, charlie, dan,
        // diana, evan, frank, grace, harry, jack, jake, jim, joe, jordan, josh,
        // justin, kate, kim, kyle, lily, logan, luke, mark, mary, max, mike,
        // morgan, nancy, nick, noah, olivia, pat, paul, peter, robin, sam, scott,
        // steve, taylor, tim, tom, tony, tyler, victoria, william)
        "aaron", "adam", "alex", "alice", "alison", "amanda", "amy", "andrew", "angela",
        "anna", "brandon", "brian", "brooke", "cameron", "carl", "chris", "christian", "christina",
        "claude", "connor", "daniel", "dave", "david", "dylan", "edward", "elizabeth",
        "emily", "emma", "eric", "ethan", "gary", "george", "greg", "hannah", "heather",
        "henry", "jacob", "james", "jane", "jason", "jeff", "jennifer", "jenny", "jessica",
        "john", "jonathan", "julia", "karen", "katie", "kevin", "laura", "lauren", "linda",
        "lisa", "matt", "matthew", "megan", "michael", "nathan", "nicole", "patrick",
        "rachel", "rebecca", "richard", "robert", "ryan", "samantha", "sarah", "sean",
        "sophia", "stephanie", "steven", "susan", "thomas",
        // Tech / brands — unambiguous only (removed: apple, mac)
        "google", "tesla", "amazon", "microsoft", "samsung", "netflix", "spotify",
        "instagram", "facebook", "youtube", "reddit", "github", "android", "iphone",
        "ipad", "siri", "alexa",
        // Places
        "america", "california", "england", "europe", "london", "paris", "texas",
        // Days / months — unambiguous only (removed: march, may, august)
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "april", "june", "july",
        "september", "october", "november", "december",
    ]

    /// Maps apostrophe-stripped lowercase forms to their contracted spelling.
    /// Shared with SwipeDecoder for tap-based autocorrect.
    static let contractions: [String: String] = [
        "dont":     "don't",
        "doesnt":   "doesn't",
        "didnt":    "didn't",
        "wont":     "won't",
        "wouldnt":  "wouldn't",
        "shouldnt": "shouldn't",
        "couldnt":  "couldn't",
        "cant":     "can't",
        "isnt":     "isn't",
        "arent":    "aren't",
        "wasnt":    "wasn't",
        "werent":   "weren't",
        "hasnt":    "hasn't",
        "havent":   "haven't",
        "hadnt":    "hadn't",
        "mustnt":   "mustn't",
        "neednt":   "needn't",
        "youre":    "you're",
        "theyre":   "they're",
        "weve":     "we've",
        "youve":    "you've",
        "theyve":   "they've",
        "ive":      "I've",
        "youll":    "you'll",
        "theyll":   "they'll",
        "well":     "we'll",
        "ill":      "I'll",
        "shell":    "she'll",
        "hell":     "he'll",
        "thats":    "that's",
        "whats":    "what's",
        "whos":     "who's",
        "heres":    "here's",
        "theres":   "there's",
        "lets":     "let's",
        "im":       "I'm",
        "hes":      "he's",
        "shes":     "she's",
        "itll":     "it'll",
        "thatll":   "that'll",
        "wholl":    "who'll",
    ]

    /// Maps real words to their apostrophe'd alternative.
    /// Used when the user taps the apostrophe button after typing a word.
    /// Includes both ambiguous real-word pairs AND stripped contraction forms.
    static let apostropheAlternatives: [String: String] = {
        // Start with all stripped contractions (dont → don't, etc.)
        var map = contractions
        // Add real-word ambiguous pairs not already in the contractions map
        map["were"] = "we're"
        map["wed"] = "we'd"
        map["id"] = "I'd"
        map["its"] = "it's"
        map["shed"] = "she'd"
        map["hed"] = "he'd"
        map["theyd"] = "they'd"
        map["youd"] = "you'd"
        return map
    }()

    init() {
        loadWords()
    }

    private func loadWords() {
        guard let url = Bundle(for: type(of: self)).url(forResource: "words", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        let allWords = contents.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0.count >= 1 }

        wordList = allWords
        words = Set(allWords)

        // Build frequency index (position in file = rank)
        for (i, word) in allWords.enumerated() {
            if frequencyIndex[word] == nil {
                frequencyIndex[word] = i
            }
        }

        // Index by first-last letter pair for fast candidate lookup
        for word in allWords {
            guard let first = word.first, let last = word.last else { continue }
            let key = "\(first)-\(last)"
            wordsByFirstLast[key, default: []].append(word)
        }
    }

    func contains(_ word: String) -> Bool {
        words.contains(word.lowercased())
    }

    /// Find candidate words matching first letter, last letter, and approximate length.
    func candidates(startingWith first: Character,
                    endingWith last: Character,
                    lengthRange: ClosedRange<Int>) -> [String] {
        let key = "\(first.lowercased())-\(last.lowercased())"
        guard let pool = wordsByFirstLast[key] else { return [] }
        return pool.filter { lengthRange.contains($0.count) }
    }

    /// Return top N most frequent words, optionally excluding some.
    func predictNextWords(excluding: Set<String> = [], limit: Int = 3) -> [String] {
        var results: [String] = []
        for word in wordList {
            if !excluding.contains(word) {
                results.append(word)
                if results.count >= limit { break }
            }
        }
        return results
    }

    /// Return words matching a prefix, frequency-ordered.
    func wordsWithPrefix(_ prefix: String, limit: Int = 3) -> [String] {
        let p = prefix.lowercased()
        var results: [String] = []
        for word in wordList {
            if word.hasPrefix(p) {
                results.append(word)
                if results.count >= limit { break }
            }
        }
        return results
    }

    /// Return the frequency rank of a word (0 = most common). Returns wordList.count if not found.
    func frequencyRank(of word: String) -> Int {
        frequencyIndex[word.lowercased()] ?? wordList.count
    }
}
