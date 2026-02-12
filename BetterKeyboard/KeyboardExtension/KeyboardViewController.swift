import UIKit

class KeyboardViewController: UIInputViewController {

    private var ringView: RingView!
    private var wordDictionary: WordDictionary!
    private var swipeDecoder: SwipeDecoder!
    private var isShifted = false

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

        // Extract the last word (everything between the trailing space and the prior space/start)
        let trimmed = before.dropLast() // remove trailing space
        let lastSpace = trimmed.lastIndex(of: " ") ?? trimmed.startIndex
        let wordStart = lastSpace == trimmed.startIndex ? lastSpace : trimmed.index(after: lastSpace)
        let lastWord = String(trimmed[wordStart...])
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
        guard !isShifted else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let shouldShift = before.isEmpty
            || before.hasSuffix(". ")
            || before.hasSuffix("! ")
            || before.hasSuffix("? ")
            || before.hasSuffix("\n")
        if shouldShift {
            isShifted = true
            ringView.updateShiftAppearance(isShifted: true)
        }
    }
}

// MARK: - RingViewDelegate

extension KeyboardViewController: RingViewDelegate {

    func ringView(_ ringView: RingView, didTapLetter letter: Character) {
        var text = String(letter)
        if isShifted {
            text = text.uppercased()
            isShifted = false
            ringView.updateShiftAppearance(isShifted: false)
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

    func ringView(_ ringView: RingView, didSwipeWord slots: [KeySlot]) {
        guard let word = swipeDecoder.decode(visitedSlots: slots) else { return }
        var text = word
        // Capitalize proper nouns (before shift, so "Claude" not "claude")
        if WordDictionary.properNouns.contains(text.lowercased()) && !text.contains("'") {
            text = text.prefix(1).uppercased() + text.dropFirst()
        }
        if isShifted {
            text = text.prefix(1).uppercased() + text.dropFirst()
            isShifted = false
            ringView.updateShiftAppearance(isShifted: false)
        }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let prefix = (!before.isEmpty && !before.hasSuffix(" ")) ? " " : ""
        let afterInput = textDocumentProxy.documentContextAfterInput ?? ""
        let suffix = afterInput.hasPrefix(" ") ? "" : " "
        textDocumentProxy.insertText(prefix + text + suffix)
        checkAutoShift()
    }

    func ringView(_ ringView: RingView, didTapShift: Void) {
        isShifted.toggle()
        ringView.updateShiftAppearance(isShifted: isShifted)
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
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if ".?!,".contains(character) && before.hasSuffix(" ") && !before.isEmpty {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(String(character))
        checkAutoShift()
    }

    func ringView(_ ringView: RingView, didMoveCursor offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func ringView(_ ringView: RingView, didJumpToEnd: Void) {
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        if !after.isEmpty {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: after.count)
        }
        checkAutoShift()
    }
}
