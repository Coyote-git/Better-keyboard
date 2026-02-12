import UIKit

class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {

    private var ringView: RingView!
    private var wordDictionary: WordDictionary!
    private var swipeDecoder: SwipeDecoder!
    private var isShifted = false
    private var blockingPress: UILongPressGestureRecognizer?
    private var blockingPan: UIPanGestureRecognizer?
    private var poisonTimer: Timer?
    private var allowInputModeSwitch = false

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

        ringView.isExclusiveTouch = true
        view.isExclusiveTouch = true

        setupBlockingGestures()

        // Continuously re-poison system gestures (they may be re-added lazily)
        poisonTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poisonSystemGestures()
        }
    }

    // MARK: - Block keyboard switching

    /// Tell the system we handle input mode switching ourselves.
    /// This may suppress the system's swipe-to-switch gesture entirely.
    override var needsInputModeSwitchKey: Bool { false }

    /// Override the system's keyboard-switch entry point.
    /// Only allow switching when we explicitly set the flag (e.g. from a globe button).
    override func advanceToNextInputMode() {
        guard allowInputModeSwitch else { return }
        super.advanceToNextInputMode()
    }

    override func handleInputModeList(from view: UIView, with event: UIEvent) {
        guard allowInputModeSwitch else { return }
        super.handleInputModeList(from: view, with: event)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        ringView.configure(viewSize: view.bounds.size)
        poisonSystemGestures()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        poisonSystemGestures()
        checkAutoShift()
    }

    /// Add gesture recognizers that claim touches before the system can.
    /// A zero-duration long press fires on touch-down (wins the race against pans).
    /// The pan is kept as backup. Both have cancelsTouchesInView=false so our
    /// custom touchesBegan/Moved/Ended still works.
    private func setupBlockingGestures() {
        // Primary: long press at 0s fires immediately on touch-down
        let press = UILongPressGestureRecognizer(target: self, action: #selector(blockingPressFired(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delaysTouchesEnded = false
        press.delegate = self
        ringView.addGestureRecognizer(press)
        blockingPress = press

        // Backup: pan on the parent view
        let pan = UIPanGestureRecognizer(target: self, action: #selector(blockingPanFired(_:)))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = self
        view.addGestureRecognizer(pan)
        blockingPan = pan
    }

    @objc private func blockingPressFired(_ gesture: UILongPressGestureRecognizer) {
        // Intentionally empty — exists to claim the touch immediately
    }

    @objc private func blockingPanFired(_ gesture: UIPanGestureRecognizer) {
        // Intentionally empty — exists to claim the pan gesture
    }

    /// Nuclear: walk the entire view hierarchy (up AND down) and disable every
    /// gesture recognizer we didn't add. Re-run on a timer because the system
    /// may lazily (re-)attach recognizers after layout.
    private func poisonSystemGestures() {
        let ours: Set<ObjectIdentifier> = [
            blockingPress.map { ObjectIdentifier($0) },
            blockingPan.map { ObjectIdentifier($0) },
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        // Walk UP from our view to the root
        var current: UIView? = view
        while let v = current {
            poisonRecognizers(on: v, ours: ours)
            current = v.superview
        }

        // Walk DOWN through all subviews
        poisonSubtree(view, ours: ours)
    }

    private func poisonRecognizers(on v: UIView, ours: Set<ObjectIdentifier>) {
        for gr in v.gestureRecognizers ?? [] {
            guard !ours.contains(ObjectIdentifier(gr)) else { continue }
            gr.isEnabled = false
            if let blocker = blockingPress {
                gr.require(toFail: blocker)
            }
        }
    }

    private func poisonSubtree(_ v: UIView, ours: Set<ObjectIdentifier>) {
        for sub in v.subviews {
            poisonRecognizers(on: sub, ours: ours)
            poisonSubtree(sub, ours: ours)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Force system gesture recognizers to wait for ours to fail (it won't)
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    // MARK: - Auto-capitalize

    /// Auto-capitalize standalone "i" → "I" after inserting a space.
    private func autoCorrectStandaloneI() {
        guard let before = textDocumentProxy.documentContextBeforeInput else { return }
        // Check for " i " pattern (space + i + space we just inserted)
        if before.hasSuffix(" i ") {
            // Delete " i " (3 chars), reinsert as " I "
            for _ in 0..<3 { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(" I ")
        } else if before == "i " && before.count == 2 {
            // "i" at very start of input
            for _ in 0..<2 { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText("I ")
        }
    }

    /// Enable auto-shift at sentence boundaries.
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
            // Double space → period
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

    func ringView(_ ringView: RingView, didMoveCursorLeft: Void) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)

    }

    func ringView(_ ringView: RingView, didMoveCursorRight: Void) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)

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

        checkAutoShift()
    }

    func ringView(_ ringView: RingView, didJumpToEnd: Void) {
        // Jump cursor to the end of all text
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        if !after.isEmpty {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: after.count)
        }

    }

    func ringView(_ ringView: RingView, didTapPunctuation character: Character) {
        // Smart punctuation: remove trailing space before sentence punctuation
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if ".?!,".contains(character) && before.hasSuffix(" ") && !before.isEmpty {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(String(character))

        checkAutoShift()
    }

}
