import Foundation

/// Loads and queries a bundled word list for swipe decoding.
class WordDictionary {

    private var words: Set<String> = []
    private var wordsByFirstLast: [String: [String]] = [:]  // "t-e" → ["the", "there", ...]
    private var frequencyIndex: [String: Int] = [:]         // word → rank (0 = most common)
    /// Frequency-ordered word list (first = most common)
    private(set) var wordList: [String] = []

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
