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

        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 320)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        ringView.configure(viewSize: view.bounds.size)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshPredictions()
    }

    // MARK: - Predictions

    private func refreshPredictions() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""

        if before.isEmpty || before.hasSuffix(" ") {
            // Cursor after a space (or at start) — show top-frequency words
            let predictions = wordDictionary.predictNextWords(limit: 3)
            ringView.updatePredictions(predictions)
        } else {
            // Cursor mid-word — show prefix completions
            let words = before.components(separatedBy: " ")
            let partial = words.last ?? ""
            if !partial.isEmpty {
                let completions = wordDictionary.wordsWithPrefix(partial, limit: 3)
                ringView.updatePredictions(completions)
            } else {
                let predictions = wordDictionary.predictNextWords(limit: 3)
                ringView.updatePredictions(predictions)
            }
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
        } else {
            text = text.lowercased()
        }
        textDocumentProxy.insertText(text)
        refreshPredictions()
    }

    func ringView(_ ringView: RingView, didTapSpace: Void) {
        textDocumentProxy.insertText(" ")
        refreshPredictions()
    }

    func ringView(_ ringView: RingView, didTapBackspace: Void) {
        textDocumentProxy.deleteBackward()
        refreshPredictions()
    }

    func ringView(_ ringView: RingView, didSwipeWord slots: [KeySlot]) {
        guard let word = swipeDecoder.decode(visitedSlots: slots) else { return }
        var text = word
        if isShifted {
            text = text.prefix(1).uppercased() + text.dropFirst()
            isShifted = false
        }
        let afterInput = textDocumentProxy.documentContextAfterInput ?? ""
        let suffix = afterInput.hasPrefix(" ") ? "" : " "
        textDocumentProxy.insertText(text + suffix)
        refreshPredictions()
    }

    func ringView(_ ringView: RingView, didTapShift: Void) {
        isShifted.toggle()
    }

    func ringView(_ ringView: RingView, didTapReturn: Void) {
        textDocumentProxy.insertText("\n")
        refreshPredictions()
    }

    func ringView(_ ringView: RingView, didMoveCursorLeft: Void) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
        refreshPredictions()
    }

    func ringView(_ ringView: RingView, didMoveCursorRight: Void) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
        refreshPredictions()
    }

    func ringView(_ ringView: RingView, didDeleteWord: Void) {
        // Delete backward until we hit a space or run out of text
        // First skip any trailing spaces
        while let before = textDocumentProxy.documentContextBeforeInput,
              before.hasSuffix(" ") {
            textDocumentProxy.deleteBackward()
        }
        // Then delete the word itself
        while let before = textDocumentProxy.documentContextBeforeInput,
              !before.isEmpty,
              !before.hasSuffix(" ") {
            textDocumentProxy.deleteBackward()
        }
        refreshPredictions()
    }

    func ringView(_ ringView: RingView, didTapPrediction word: String) {
        // Delete the current partial word, then insert the predicted word
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if !before.isEmpty && !before.hasSuffix(" ") {
            let words = before.components(separatedBy: " ")
            let partial = words.last ?? ""
            for _ in 0..<partial.count {
                textDocumentProxy.deleteBackward()
            }
        }
        let afterInput = textDocumentProxy.documentContextAfterInput ?? ""
        let suffix = afterInput.hasPrefix(" ") ? "" : " "
        textDocumentProxy.insertText(word + suffix)
        refreshPredictions()
    }
}
