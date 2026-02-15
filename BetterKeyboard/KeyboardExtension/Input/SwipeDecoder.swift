import CoreGraphics

/// Matches a sequence of velocity-weighted keys to a dictionary word.
/// Uses alignment scoring: word letters are greedily matched against the
/// weighted key sequence, with penalties for missed letters, low-weight
/// matches, and unmatched anchor keys.
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

    // MARK: - Scoring constants

    /// Letter exists in key sequence but couldn't match in order (plausible miss)
    private let nearPathMissPenalty: CGFloat = 12.0
    /// Letter doesn't appear in key sequence at ALL (phantom — never near the path)
    private let absentMissPenalty: CGFloat = 20.0
    private let weightMismatchScale: CGFloat = 2.0
    private let unmatchedAnchorPenalty: CGFloat = 6.0
    private let coveragePenaltyScale: CGFloat = 15.0
    private let lengthBonus: CGFloat = -3.5
    private let anchorWeightThreshold: CGFloat = 0.5
    /// Penalty applied when trying alternate (second-to-last anchor) as end letter
    private let alternateEndPenalty: CGFloat = 5.0

    init(dictionary: WordDictionary) {
        self.dictionary = dictionary
    }

    // MARK: - Main decode

    func decode(weightedKeys: [WeightedKey]) -> String? {
        return decodeTopN(weightedKeys: weightedKeys, n: 1).first
    }

    /// Returns the top N decoded words, scored best to worst.
    /// Used by prediction bar to show alternatives after a swipe.
    func decodeTopN(weightedKeys: [WeightedKey], n: Int = 3) -> [String] {
        guard !weightedKeys.isEmpty else { return [] }

        // Separate anchors (high-weight) from all keys
        let anchors = weightedKeys.filter { $0.weight >= anchorWeightThreshold }
        let anchorCount = anchors.count
        let keyCount = weightedKeys.count

        guard let firstKey = weightedKeys.first else { return [] }
        let firstLetter = firstKey.slot.letter

        // Primary last letter: last anchor (or last key if no anchors)
        let primaryLastLetter = (anchors.last ?? weightedKeys.last!).slot.letter

        // Alternate last letter for overshoot handling: second-to-last anchor
        let alternateLastLetter: Character? = anchors.count >= 2
            ? anchors[anchors.count - 2].slot.letter : nil

        // Length range: flexible around anchor count
        let minLen = max(2, anchorCount - 2)
        let maxLen = max(keyCount, anchorCount + 3)

        // Track top N results (word, score) sorted by score ascending
        var topResults: [(word: String, score: CGFloat)] = []

        func insertResult(_ word: String, _ score: CGFloat) {
            // Skip duplicates (same word from different end-letter paths)
            if topResults.contains(where: { $0.word == word }) { return }
            if topResults.count < n {
                topResults.append((word, score))
                topResults.sort { $0.score < $1.score }
            } else if score < topResults.last!.score {
                topResults[topResults.count - 1] = (word, score)
                topResults.sort { $0.score < $1.score }
            }
        }

        // Try primary end letter, then alternate (with penalty)
        let endLetters: [(Character, CGFloat)] = {
            var ends = [(primaryLastLetter, CGFloat(0.0))]
            if let alt = alternateLastLetter, alt != primaryLastLetter {
                ends.append((alt, alternateEndPenalty))
            }
            return ends
        }()

        for (lastLetter, endPenalty) in endLetters {
            let candidates = dictionary.candidates(
                startingWith: firstLetter,
                endingWith: lastLetter,
                lengthRange: minLen...maxLen
            )

            for word in candidates {
                let nounPenalty: CGFloat = WordDictionary.properNouns.contains(word) ? 8.0 : 0.0

                if let score = alignmentScore(word: word, keys: weightedKeys) {
                    let total = score + endPenalty + nounPenalty
                    insertResult(word, total)
                }
            }

            // Check contractions with this end letter
            for (stripped, contracted) in Self.contractions {
                let strippedChars = Array(stripped.uppercased())
                guard let firstChar = strippedChars.first,
                      let lastChar = strippedChars.last,
                      firstChar == firstLetter,
                      lastChar == lastLetter else { continue }

                if let score = alignmentScore(word: stripped, keys: weightedKeys) {
                    let bonus: CGFloat = Self.ambiguousContractions.contains(stripped) ? 0 : -5.0
                    let total = score + bonus + endPenalty
                    insertResult(contracted, total)
                }
            }
        }

        return topResults.map { $0.word }
    }

    // MARK: - Alignment scoring

    /// Score how well a word aligns with the weighted key sequence.
    /// Lower = better. Returns nil if alignment is too poor.
    ///
    /// Algorithm:
    /// 1. Collapse consecutive duplicate letters in the word
    /// 2. Require first letter match
    /// 3. Greedy forward alignment of collapsed letters to keys
    /// 4. Require last letter match for words > 3 letters
    /// 5. Reject if > half the letters are missed
    private func alignmentScore(word: String, keys: [WeightedKey]) -> CGFloat? {
        let wordChars = Array(word.uppercased())
        guard wordChars.count >= 2 else { return nil }

        // Collapse consecutive duplicates: "hello" → "helo"
        var collapsed: [Character] = []
        for ch in wordChars {
            if collapsed.last != ch { collapsed.append(ch) }
        }

        // Require first letter match
        guard collapsed.first == keys.first?.slot.letter else { return nil }

        // Build set of all letters present anywhere in the key sequence
        let allKeyLetters = Set(keys.map { $0.slot.letter })

        // Greedy forward alignment: match each collapsed letter to earliest matching key.
        // Track near-path misses (letter exists in keys but ordering blocked)
        // vs absent misses (letter nowhere in key sequence — phantom letter).
        var matchedKeyIndices: [Int] = []
        var nearPathMisses = 0
        var absentMisses = 0
        var searchFrom = 0

        for ch in collapsed {
            var found = false
            for k in searchFrom..<keys.count {
                if keys[k].slot.letter == ch {
                    matchedKeyIndices.append(k)
                    searchFrom = k + 1
                    found = true
                    break
                }
            }
            if !found {
                if allKeyLetters.contains(ch) {
                    nearPathMisses += 1
                } else {
                    absentMisses += 1
                }
            }
        }

        let totalMisses = nearPathMisses + absentMisses

        // Require last letter match for words > 3 letters
        if collapsed.count > 3 {
            let lastCollapsed = collapsed.last!
            guard let lastMatched = matchedKeyIndices.last else { return nil }
            if keys[lastMatched].slot.letter != lastCollapsed { return nil }
        }

        // Reject if more than half the letters are missed
        if totalMisses > collapsed.count / 2 { return nil }

        // --- Score components (lower = better) ---

        // 1. Missed letter penalty (two-tier: phantom letters cost much more)
        let missed = CGFloat(nearPathMisses) * nearPathMissPenalty
                   + CGFloat(absentMisses) * absentMissPenalty

        // 2. Weight alignment: prefer matching high-weight keys
        var weightCost: CGFloat = 0
        for idx in matchedKeyIndices {
            weightCost += (1.0 - keys[idx].weight)
        }
        weightCost *= weightMismatchScale

        // 3. Unmatched anchor penalty: high-weight keys not used by the word
        let matchedSet = Set(matchedKeyIndices)
        var anchorCost: CGFloat = 0
        for (i, key) in keys.enumerated() {
            if key.weight >= anchorWeightThreshold && !matchedSet.contains(i) {
                anchorCost += key.weight * unmatchedAnchorPenalty
            }
        }

        // 4. Coverage: match should span the key sequence
        let coverageCost: CGFloat
        if matchedKeyIndices.count >= 2 {
            let span = matchedKeyIndices.last! - matchedKeyIndices.first! + 1
            let spanRatio = CGFloat(span) / CGFloat(keys.count)
            coverageCost = (1.0 - spanRatio) * coveragePenaltyScale
        } else {
            coverageCost = coveragePenaltyScale
        }

        // 5. Length bonus: prefer longer words
        let lenBonus = CGFloat(wordChars.count) * lengthBonus

        // 6. Frequency: prefer common words
        let rank = dictionary.frequencyRank(of: word)
        let freqCost = min(CGFloat(rank) * 0.03, 10.0)

        // 7. Unsupported double-letter penalty: if the word has consecutive
        //    duplicate letters (e.g. "off") but the key sequence doesn't have
        //    that letter appearing twice, the swipe didn't intend the double.
        var unsupportedDoubles = 0
        var checkedLetters = Set<Character>()
        for i in 1..<wordChars.count {
            if wordChars[i] == wordChars[i - 1] && !checkedLetters.contains(wordChars[i]) {
                checkedLetters.insert(wordChars[i])
                let keyInstances = keys.filter { $0.slot.letter == wordChars[i] }.count
                if keyInstances < 2 { unsupportedDoubles += 1 }
            }
        }
        let doublePenalty = CGFloat(unsupportedDoubles) * 8.0

        return missed + weightCost + anchorCost + coverageCost + lenBonus + freqCost + doublePenalty
    }
}
