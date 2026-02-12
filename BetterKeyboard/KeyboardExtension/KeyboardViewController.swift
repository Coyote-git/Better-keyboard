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

    private func autoCorrectStandaloneI() {
        guard let before = textDocumentProxy.documentContextBeforeInput else { return }
        if before.hasSuffix(" i ") {
            for _ in 0..<3 { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(" I ")
        } else if before == "i " && before.count == 2 {
            for _ in 0..<2 { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText("I ")
        }
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
            autoCorrectStandaloneI()
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
