import UIKit

class KeyboardViewController: UIInputViewController {

    private var ringView: RingView!
    private var wordDictionary: WordDictionary!
    private var swipeDecoder: SwipeDecoder!
    private var isShifted = false
    private var isCapsLocked = false
    private var lastShiftTapTime: TimeInterval = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        wordDictionary = WordDictionary()
        swipeDecoder = SwipeDecoder(dictionary: wordDictionary)

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
        ringView.configure(viewSize: view.bounds.size)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkAutoShift()
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
}

// MARK: - RingViewDelegate

extension KeyboardViewController: RingViewDelegate {

    func ringView(_ ringView: RingView, didTapLetter letter: Character) {
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
    }

    func ringView(_ ringView: RingView, didTapBackspace: Void) {
        textDocumentProxy.deleteBackward()
        checkAutoShift()
    }

    func ringView(_ ringView: RingView, didSwipeWord keys: [WeightedKey]) {
        guard let word = swipeDecoder.decode(weightedKeys: keys) else { return }
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

        // Insert space before if needed, and autocorrect previous word
        // (fixes "i" not capitalizing when followed by a swipe)
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if !before.isEmpty && !before.hasSuffix(" ") {
            textDocumentProxy.insertText(" ")
            autoCorrectLastWord()
        }

        let afterInput = textDocumentProxy.documentContextAfterInput ?? ""
        let suffix = afterInput.hasPrefix(" ") ? "" : " "
        textDocumentProxy.insertText(text + suffix)
        checkAutoShift()
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
    }

    func ringView(_ ringView: RingView, didDeleteWord: Void) {
        while let before = textDocumentProxy.documentContextBeforeInput,
              before.hasSuffix(" ") {
            textDocumentProxy.deleteBackward()
        }
        while let before = textDocumentProxy.documentContextBeforeInput,
              !before.isEmpty,
              !before.hasSuffix(" ") {
            textDocumentProxy.deleteBackward()
        }
        checkAutoShift()
    }

    func ringView(_ ringView: RingView, didTapPunctuation character: Character) {
        // Apostrophe toggle: replace last word with contracted version if one exists
        if character == "'" {
            if tryApostropheToggle() { return }
        }

        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if ".?!,".contains(character) && before.hasSuffix(" ") && !before.isEmpty {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(String(character))
        checkAutoShift()
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
}
