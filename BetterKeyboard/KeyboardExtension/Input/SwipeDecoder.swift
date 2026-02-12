import CoreGraphics

/// Matches a sequence of visited KeySlots to a dictionary word.
/// On a circular layout, swiping between keys inevitably passes through
/// intermediate keys. The decoder uses subsequence matching: a word matches
/// if its letters appear in order within the visited key sequence.
class SwipeDecoder {

    private let dictionary: WordDictionary

    // MARK: - Contractions

    /// Maps apostrophe-stripped forms to their contracted spelling.
    /// Only includes unambiguous cases (e.g. "were" is NOT "we're").
    private static let contractions: [String: String] = [
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
        "well":     "we'll",    // note: also a plain word — handled by score bonus
        "ill":      "I'll",     // same — "ill" is a word too
        "shell":    "she'll",   // same
        "hell":     "he'll",    // same
        "thats":    "that's",
        "whats":    "what's",
        "whos":     "who's",
        "heres":    "here's",
        "theres":   "there's",
        "lets":     "let's",
        "im":       "I'm",
        "youre":    "you're",
        "hes":      "he's",
        "shes":     "she's",
        "itll":     "it'll",
        "thatll":   "that'll",
        "wholl":    "who'll",
    ]

    /// Contractions that are also valid standalone words — only prefer
    /// the contraction if the score is significantly better.
    private static let ambiguousContractions: Set<String> = [
        "well", "ill", "shell", "hell", "lets", "hes", "shes",
    ]

    init(dictionary: WordDictionary) {
        self.dictionary = dictionary
    }

    /// Max slots to trim from the end to handle overshoot (e.g. "up" → "upg")
    private let maxTailTrim = 2

    func decode(visitedSlots: [KeySlot]) -> String? {
        guard !visitedSlots.isEmpty else { return nil }

        let visited = visitedSlots.map { $0.letter }

        // 1. Exact match (unlikely on circular layout, but fast check)
        let rawLetters = String(visited).lowercased()
        if dictionary.contains(rawLetters) {
            return rawLetters
        }

        let firstLetter = visited.first!

        var bestWord: String?
        var bestScore = CGFloat.infinity
        var bestContraction: String?
        var bestContractionScore = CGFloat.infinity

        // Try the full visited sequence, then trimmed versions (drop 1-2 from end)
        // to handle overshoot. Trimmed versions get a penalty per dropped slot.
        let trimLimit = min(maxTailTrim, visited.count - 1)

        for trim in 0...trimLimit {
            let trimmedVisited = Array(visited.prefix(visited.count - trim))
            let trimmedSlots = Array(visitedSlots.prefix(visitedSlots.count - trim))
            guard trimmedVisited.count >= 2 else { continue }

            let lastLetter = trimmedVisited.last!
            let trimPenalty = CGFloat(trim) * 6.0

            // 2. Subsequence matching against dictionary
            let candidates = dictionary.candidates(
                startingWith: firstLetter,
                endingWith: lastLetter,
                lengthRange: 2...trimmedVisited.count
            )

            for word in candidates {
                if let score = subsequenceScore(word: word, visited: trimmedVisited, slots: trimmedSlots) {
                    let freqPenalty = CGFloat(dictionary.frequencyRank(of: word)) * 0.02
                    let total = score + freqPenalty + trimPenalty
                    if total < bestScore {
                        bestScore = total
                        bestWord = word
                    }
                }
            }

            // 3. Check contractions
            for (stripped, contracted) in Self.contractions {
                let strippedChars = Array(stripped.uppercased())
                guard let firstChar = strippedChars.first,
                      let lastChar = strippedChars.last,
                      firstChar == firstLetter,
                      lastChar == lastLetter else { continue }

                if let score = subsequenceScore(word: stripped, visited: trimmedVisited, slots: trimmedSlots) {
                    let bonus: CGFloat = Self.ambiguousContractions.contains(stripped) ? 0 : -5.0
                    let total = score + bonus + trimPenalty
                    if total < bestContractionScore {
                        bestContractionScore = total
                        bestContraction = contracted
                    }
                }
            }
        }

        // Pick the best overall
        if let contraction = bestContraction, bestContractionScore < bestScore {
            return contraction
        }

        // Return dictionary match or nil (no gibberish fallback)
        return bestWord
    }

    /// Check if word's letters appear as a subsequence of visited keys.
    /// Returns a score (lower = better) or nil if not a subsequence.
    ///
    /// Score factors:
    /// - Tightness: fewer skipped keys between matched letters is better
    /// - Coverage: matched letters should span most of the visited sequence
    /// - Word length: longer words preferred (more intentional)
    /// - Frequency: common words preferred (applied in caller)
    private func subsequenceScore(word: String, visited: [Character],
                                  slots: [KeySlot]) -> CGFloat? {
        let wordChars = Array(word.uppercased())
        guard wordChars.count >= 2 else { return nil }

        // Collapse consecutive duplicate letters in the word for matching.
        // "sloppy" → "slopy" so we only need one P in the visited sequence.
        // We track which collapsed chars map to double letters for scoring.
        var collapsed: [Character] = []
        for ch in wordChars {
            if collapsed.last != ch {
                collapsed.append(ch)
            }
        }

        // Find the subsequence match with minimal total gaps
        var matchIndices: [Int] = []
        var searchFrom = 0

        for ch in collapsed {
            var found = false
            for i in searchFrom..<visited.count {
                if visited[i] == ch {
                    matchIndices.append(i)
                    searchFrom = i + 1
                    found = true
                    break
                }
            }
            if !found { return nil }  // Not a subsequence
        }

        // Score: lower is better

        // 1. Gap penalty: total number of unmatched visited keys between matched ones
        var totalGap = 0
        for i in 1..<matchIndices.count {
            totalGap += (matchIndices[i] - matchIndices[i - 1] - 1)
        }

        // 2. Span ratio: the match should cover a good portion of the visited sequence
        let span = matchIndices.last! - matchIndices.first! + 1
        let spanRatio = CGFloat(span) / CGFloat(visited.count)
        let spanPenalty = (1.0 - spanRatio) * 30.0

        // 3. Word length bonus: prefer longer words (more intentional)
        let lengthBonus = -CGFloat(wordChars.count) * 2.0

        return CGFloat(totalGap) * 3.0 + spanPenalty + lengthBonus
    }
}
