import UIKit

class KeyboardViewController: UIInputViewController {

    private var ringView: RingView!
    private var wordDictionary: WordDictionary!
    private var swipeDecoder: SwipeDecoder!
    private var isShifted = false
    private var isCapsLocked = false
    private var lastShiftTapTime: TimeInterval = 0

    // MARK: - Prediction state

    /// What tapping a prediction button does.
    private enum PredictionMode {
        case alternatives   // after swipe — tap replaces last word
        case completion     // mid-word — tap deletes partial, inserts full word
        case suggestion     // after space — tap inserts word
    }

    private var predictionMode: PredictionMode = .suggestion
    /// Stored alternatives from the last swipe decode (excludes the inserted word).
    private var lastSwipeAlternatives: [String] = []

    // MARK: - Quote/bracket tracking

    /// Tracks unmatched opening quotes so we can distinguish open vs close.
    /// Incremented on opening, decremented on closing. Reset when keyboard appears.
    private var unmatchedDoubleQuotes = 0
    private var unmatchedSingleQuotes = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        wordDictionary = WordDictionary()
        swipeDecoder = SwipeDecoder(dictionary: wordDictionary)

        // Ring view — fills entire keyboard, predictions in top strip
        ringView = RingView(frame: .zero)
        ringView.delegate = self
        ringView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ringView)

        NSLayoutConstraint.activate([
            ringView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ringView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ringView.topAnchor.constraint(equalTo: view.topAnchor),
            ringView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 290)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        ringView.configure(viewSize: ringView.bounds.size)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Reset quote tracking — we can't reliably scan existing text for unmatched quotes
        unmatchedDoubleQuotes = 0
        unmatchedSingleQuotes = 0
        checkAutoShift()
        updatePredictions()
    }

    // MARK: - Predictions

    private func updatePredictions() {
        switch predictionMode {
        case .alternatives:
            ringView.updatePredictions( lastSwipeAlternatives)

        case .completion:
            let partial = extractPartialWord()
            if partial.count >= 1 {
                let completions = wordDictionary.wordsWithPrefix(partial, limit: 3)
                ringView.updatePredictions( completions)
            } else {
                // No partial word — fall back to suggestions
                predictionMode = .suggestion
                let words = wordDictionary.predictNextWords(limit: 3)
                ringView.updatePredictions( words)
            }

        case .suggestion:
            let words = wordDictionary.predictNextWords(limit: 3)
            ringView.updatePredictions( words)
        }
    }

    /// Extract the current partial word from text before cursor.
    /// Returns "" if cursor is after whitespace or field is empty.
    private func extractPartialWord() -> String {
        guard let before = textDocumentProxy.documentContextBeforeInput,
              !before.isEmpty,
              let last = before.last, !last.isWhitespace else { return "" }
        let components = before.split(whereSeparator: { $0.isWhitespace })
        return components.last.map(String.init) ?? ""
    }

    // MARK: - Quote tracking helpers

    /// Adjust unmatched quote counts when a character is about to be deleted.
    /// Call BEFORE `deleteBackward()`. Reverses the open/close decision that was
    /// made when the character was originally inserted.
    private func adjustQuoteCountsForDeletion(_ before: String) {
        guard let last = before.last else { return }
        if last == "\"" {
            if unmatchedDoubleQuotes > 0 {
                unmatchedDoubleQuotes -= 1  // undoing an opening
            } else {
                unmatchedDoubleQuotes += 1  // undoing a closing → reopen
            }
        } else if last == "'" {
            // Don't adjust if this was likely an apostrophe in a contraction
            let charBefore = before.dropLast().last
            let isApostrophe = charBefore?.isLetter == true && unmatchedSingleQuotes == 0
            if !isApostrophe {
                if unmatchedSingleQuotes > 0 {
                    unmatchedSingleQuotes -= 1
                } else {
                    unmatchedSingleQuotes += 1
                }
            }
        }
    }

    // MARK: - Auto-capitalize

    /// After a space is inserted, check the word just typed and fix
    /// contractions (dont → don't) and proper nouns (claude → Claude).
    private func autoCorrectLastWord() {
        guard let before = textDocumentProxy.documentContextBeforeInput,
              before.hasSuffix(" ") else { return }

        // Extract the last word (split on any whitespace, take the last component)
        let trimmed = before.dropLast()
        guard let lastWordSub = trimmed.split(whereSeparator: { $0.isWhitespace }).last else { return }
        let lastWord = String(lastWordSub)
        guard !lastWord.isEmpty else { return }

        let lower = lastWord.lowercased()
        var replacement: String?

        // 1. Standalone "i"
        if lower == "i" && lastWord == "i" {
            replacement = "I"
        }

        // 2. Contraction (dont → don't)
        if replacement == nil, let contracted = WordDictionary.contractions[lower],
           lastWord == lower {  // only fix if user typed it lowercase (not intentionally cased)
            replacement = contracted
        }

        // 3. Proper noun (claude → Claude)
        if replacement == nil, WordDictionary.properNouns.contains(lower),
           lastWord == lower {  // only fix if all-lowercase
            replacement = lower.prefix(1).uppercased() + lower.dropFirst()
        }

        guard let fix = replacement else { return }

        // Delete "word " and re-insert "fix "
        let deleteCount = lastWord.count + 1 // +1 for trailing space
        for _ in 0..<deleteCount { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(fix + " ")
    }

    private func checkAutoShift() {
        guard !isShifted, !isCapsLocked else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let shouldShift = before.isEmpty
            || before.hasSuffix(". ")
            || before.hasSuffix("! ")
            || before.hasSuffix("? ")
            || before.hasSuffix("\n")
        if shouldShift {
            isShifted = true
            ringView.updateShiftAppearance(isShifted: true, isCapsLocked: isCapsLocked)
        }
    }

    /// Replace the last word (+ trailing space if present) with a new word + space.
    private func replaceLastWord(with newWord: String) {
        guard let before = textDocumentProxy.documentContextBeforeInput,
              !before.isEmpty else { return }

        let hasTrailingSpace = before.hasSuffix(" ")
        let trimmed = hasTrailingSpace ? String(before.dropLast()) : before
        let components = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard let lastWordSub = components.last else { return }

        let deleteCount = lastWordSub.count + (hasTrailingSpace ? 1 : 0)
        for _ in 0..<deleteCount { textDocumentProxy.deleteBackward() }

        var text = newWord
        // Apply proper noun capitalization
        if WordDictionary.properNouns.contains(text.lowercased()) && !text.contains("'") {
            text = text.prefix(1).uppercased() + text.dropFirst()
        }
        textDocumentProxy.insertText(text + " ")
    }
}

// MARK: - RingViewDelegate

extension KeyboardViewController: RingViewDelegate {

    func ringView(_ ringView: RingView, didTapLetter letter: Character) {
        // Route symbols/punctuation through the punctuation handler so they get
        // consistent smart spacing, apostrophe toggle, etc. regardless of
        // whether they came from a button or the symbol ring.
        if !letter.isLetter && !letter.isNumber {
            self.ringView(ringView, didTapPunctuation: letter)
            return
        }

        var text = String(letter)
        if isShifted {
            text = text.uppercased()
            if !isCapsLocked {
                isShifted = false
                ringView.updateShiftAppearance(isShifted: false, isCapsLocked: false)
            }
        } else {
            text = text.lowercased()
        }
        textDocumentProxy.insertText(text)
        checkAutoShift()
        predictionMode = .completion
        updatePredictions()
    }

    func ringView(_ ringView: RingView, didTapSpace: Void) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if before.hasSuffix(" ") && !before.hasSuffix(". ") && !before.isEmpty {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
        } else {
            textDocumentProxy.insertText(" ")
            autoCorrectLastWord()
        }
        checkAutoShift()
        predictionMode = .suggestion
        updatePredictions()
    }

    func ringView(_ ringView: RingView, didTapBackspace: Void) {
        if let before = textDocumentProxy.documentContextBeforeInput {
            adjustQuoteCountsForDeletion(before)
        }
        textDocumentProxy.deleteBackward()
        checkAutoShift()
        let partial = extractPartialWord()
        predictionMode = partial.isEmpty ? .suggestion : .completion
        updatePredictions()
    }

    func ringView(_ ringView: RingView, didSwipeWord keys: [WeightedKey]) {
        // Decode top 4 to get the best + 3 alternatives
        let topResults = swipeDecoder.decodeTopN(weightedKeys: keys, n: 4)
        guard let word = topResults.first else { return }

        var text = word
        // Capitalize proper nouns (before shift, so "Claude" not "claude")
        if WordDictionary.properNouns.contains(text.lowercased()) && !text.contains("'") {
            text = text.prefix(1).uppercased() + text.dropFirst()
        }
        if isShifted {
            if isCapsLocked {
                text = text.uppercased()
            } else {
                text = text.prefix(1).uppercased() + text.dropFirst()
                isShifted = false
                ringView.updateShiftAppearance(isShifted: false, isCapsLocked: false)
            }
        }

        // Insert space before if needed. Skip space after:
        // - whitespace (obviously)
        // - opening brackets (always unambiguous)
        // - opening quotes (determined by unmatched count > 0)
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let openingBrackets: Set<Character> = ["(", "[", "{"]
        var needsSpace = false
        if let lastChar = before.last, !lastChar.isWhitespace {
            if openingBrackets.contains(lastChar) {
                needsSpace = false
            } else if lastChar == "\"" {
                // Inside quotes (just opened) → skip space; outside (just closed) → need space
                needsSpace = unmatchedDoubleQuotes == 0
            } else if lastChar == "'" {
                needsSpace = unmatchedSingleQuotes == 0
            } else {
                needsSpace = true
            }
        }
        if needsSpace {
            textDocumentProxy.insertText(" ")
            autoCorrectLastWord()
        }

        let afterInput = textDocumentProxy.documentContextAfterInput ?? ""
        let suffix = afterInput.hasPrefix(" ") ? "" : " "
        textDocumentProxy.insertText(text + suffix)
        checkAutoShift()

        // Store alternatives (skip the inserted word) for prediction bar
        lastSwipeAlternatives = Array(topResults.dropFirst())
        predictionMode = .alternatives
        updatePredictions()
    }

    func ringView(_ ringView: RingView, didTapShift: Void) {
        let now = CACurrentMediaTime()

        if isCapsLocked {
            isCapsLocked = false
            isShifted = false
        } else if (now - lastShiftTapTime) < 0.4 {
            // Double tap from any state → caps lock
            isCapsLocked = true
            isShifted = true
        } else {
            isShifted.toggle()
        }

        lastShiftTapTime = now
        ringView.updateShiftAppearance(isShifted: isShifted, isCapsLocked: isCapsLocked)
    }

    func ringView(_ ringView: RingView, didTapReturn: Void) {
        textDocumentProxy.insertText("\n")
        checkAutoShift()
        predictionMode = .suggestion
        updatePredictions()
    }

    func ringView(_ ringView: RingView, didDeleteWord: Void) {
        // Delete trailing spaces
        while let before = textDocumentProxy.documentContextBeforeInput,
              before.hasSuffix(" ") {
            textDocumentProxy.deleteBackward()
        }

        // Delete word characters, stopping at standalone quotes/brackets
        // so "hello doesn't delete the opening quote
        let brackets: Set<Character> = ["(", ")", "[", "]", "{", "}"]
        while let before = textDocumentProxy.documentContextBeforeInput,
              !before.isEmpty,
              !before.hasSuffix(" ") {
            guard let last = before.last else { break }

            // Brackets are always word boundaries — stop
            if brackets.contains(last) { break }

            // Quotes are boundaries if standalone (preceded by whitespace/nothing),
            // but mid-word apostrophes (preceded by a letter) should be deleted
            if last == "\"" || last == "'" {
                let charBefore = before.dropLast().last
                if charBefore == nil || !charBefore!.isLetter { break }
            }

            adjustQuoteCountsForDeletion(before)
            textDocumentProxy.deleteBackward()
        }

        checkAutoShift()
        predictionMode = .suggestion
        updatePredictions()
    }

    func ringView(_ ringView: RingView, didTapPunctuation character: Character) {
        // Apostrophe toggle: replace last word with contracted version if one exists
        if character == "'" {
            if tryApostropheToggle() { return }
        }

        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let hasTrailing = before.hasSuffix(" ") && !before.isEmpty

        if character == "\"" {
            if unmatchedDoubleQuotes > 0 {
                // Closing quote — eat trailing space so it hugs the word
                if hasTrailing { textDocumentProxy.deleteBackward() }
                unmatchedDoubleQuotes -= 1
            } else {
                // Opening quote — leave any space, it's separation from previous word
                unmatchedDoubleQuotes += 1
            }
        } else if character == "'" {
            // Apostrophe toggle already failed, so this is a literal '
            // Distinguish apostrophe (mid-word) from quote (standalone)
            let lastChar = before.last ?? " "
            if !lastChar.isWhitespace && unmatchedSingleQuotes == 0 {
                // After a letter with no unmatched quotes → apostrophe, not a quote
                // Eat trailing space so it hugs the word (e.g., possessive)
                if hasTrailing { textDocumentProxy.deleteBackward() }
            } else if unmatchedSingleQuotes > 0 {
                // Closing quote
                if hasTrailing { textDocumentProxy.deleteBackward() }
                unmatchedSingleQuotes -= 1
            } else {
                // Opening quote
                unmatchedSingleQuotes += 1
            }
        } else {
            // Regular punctuation — eat trailing space for chars that hug the previous word
            let eatSpaceChars: Set<Character> = [".", "?", "!", ",", ")", "]", "}"]
            if eatSpaceChars.contains(character) && hasTrailing {
                textDocumentProxy.deleteBackward()
            }
        }

        textDocumentProxy.insertText(String(character))
        checkAutoShift()
        predictionMode = .suggestion
        updatePredictions()
    }

    /// If the word immediately before the cursor has an apostrophe'd alternative,
    /// replace it and return true. Otherwise return false (insert literal apostrophe).
    private func tryApostropheToggle() -> Bool {
        guard let before = textDocumentProxy.documentContextBeforeInput,
              !before.isEmpty else { return false }

        // Swiped words have a trailing space; tapped words don't
        let hasTrailingSpace = before.hasSuffix(" ")
        let trimmed = hasTrailingSpace ? String(before.dropLast()) : before

        let components = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard let lastWordSub = components.last else { return false }
        let lastWord = String(lastWordSub)

        let lower = lastWord.lowercased()
        guard let contracted = WordDictionary.apostropheAlternatives[lower] else { return false }

        // Preserve user's capitalization: if first letter was uppercase, capitalize the replacement
        var replacement = contracted
        if let first = lastWord.first, first.isUppercase {
            replacement = replacement.prefix(1).uppercased() + replacement.dropFirst()
        }

        let deleteCount = lastWord.count + (hasTrailingSpace ? 1 : 0)
        for _ in 0..<deleteCount { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(replacement + (hasTrailingSpace ? " " : ""))
        return true
    }

    func ringView(_ ringView: RingView, didMoveCursor offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func ringView(_ ringView: RingView, didTapDismiss: Void) {
        dismissKeyboard()
    }

    func ringView(_ ringView: RingView, didJumpToEnd: Void) {
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        if !after.isEmpty {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: after.count)
        }
        checkAutoShift()
    }

    func ringView(_ ringView: RingView, didChangeTheme: Void) {
        // Theme is applied internally by RingView
    }

    func ringView(_ ringView: RingView, didSelectPrediction word: String) {
        switch predictionMode {
        case .alternatives:
            replaceLastWord(with: word)

        case .completion:
            let partial = extractPartialWord()
            for _ in 0..<partial.count { textDocumentProxy.deleteBackward() }

            var text = word
            if WordDictionary.properNouns.contains(text.lowercased()) && !text.contains("'") {
                text = text.prefix(1).uppercased() + text.dropFirst()
            }
            if isShifted && !isCapsLocked {
                text = text.prefix(1).uppercased() + text.dropFirst()
                isShifted = false
                ringView.updateShiftAppearance(isShifted: false, isCapsLocked: false)
            } else if isCapsLocked {
                text = text.uppercased()
            }
            textDocumentProxy.insertText(text + " ")

        case .suggestion:
            var text = word
            if WordDictionary.properNouns.contains(text.lowercased()) && !text.contains("'") {
                text = text.prefix(1).uppercased() + text.dropFirst()
            }
            if isShifted && !isCapsLocked {
                text = text.prefix(1).uppercased() + text.dropFirst()
                isShifted = false
                ringView.updateShiftAppearance(isShifted: false, isCapsLocked: false)
            } else if isCapsLocked {
                text = text.uppercased()
            }
            textDocumentProxy.insertText(text + " ")
        }

        checkAutoShift()
        lastSwipeAlternatives = []
        predictionMode = .suggestion
        updatePredictions()
    }
}
