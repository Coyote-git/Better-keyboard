
######################################################################
# KeyboardViewController.swift — State just before keyboard switch prevention (line 666)
# Last full write: line 100, then 19 edits
######################################################################

import UIKit

class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {

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
        disableConflictingSystemGestures()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableConflictingSystemGestures()
        refreshPredictions()
        checkAutoShift()
    }

    /// Disable system gesture recognizers (e.g. swipe-to-switch-keyboard)
    /// that conflict with our custom touch handling.
    private func disableConflictingSystemGestures() {
        // System adds swipe recognizers to the inputView's superview hierarchy
        var current: UIView? = view
        while let v = current {
            if let recognizers = v.gestureRecognizers {
                for gesture in recognizers {
                    // Disable swipe/pan recognizers we didn't create
                    if gesture is UISwipeGestureRecognizer || gesture is UIPanGestureRecognizer {
                        gesture.isEnabled = false
                    }
                }
            }
            current = v.superview
        }
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
            ringView.updateShiftAppearance(isShifted: false)
        } else {
            text = text.lowercased()
        }
        textDocumentProxy.insertText(text)
        refreshPredictions()
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
        refreshPredictions()
        checkAutoShift()
    }

    func ringView(_ ringView: RingView, didTapBackspace: Void) {
        textDocumentProxy.deleteBackward()
        refreshPredictions()
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
        let afterInput = textDocumentProxy.documentContextAfterInput ?? ""
        let suffix = afterInput.hasPrefix(" ") ? "" : " "
        textDocumentProxy.insertText(text + suffix)
        refreshPredictions()
        checkAutoShift()
    }

    func ringView(_ ringView: RingView, didTapShift: Void) {
        isShifted.toggle()
        ringView.updateShiftAppearance(isShifted: isShifted)
    }

    func ringView(_ ringView: RingView, didTapReturn: Void) {
        textDocumentProxy.insertText("\n")
        refreshPredictions()
        checkAutoShift()
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
        checkAutoShift()
    }

    func ringView(_ ringView: RingView, didTapPunctuation character: Character) {
        // Smart punctuation: remove trailing space before sentence punctuation
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if ".?!,".contains(character) && before.hasSuffix(" ") && !before.isEmpty {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(String(character))
        refreshPredictions()
        checkAutoShift()
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
        checkAutoShift()
    }
}


######################################################################
# RingView.swift — State just before keyboard switch prevention (line 666)
# Last full write: line 156, then 18 edits
######################################################################

import UIKit

protocol RingViewDelegate: AnyObject {
    func ringView(_ ringView: RingView, didTapLetter letter: Character)
    func ringView(_ ringView: RingView, didTapSpace: Void)
    func ringView(_ ringView: RingView, didTapBackspace: Void)
    func ringView(_ ringView: RingView, didSwipeWord slots: [KeySlot])
    func ringView(_ ringView: RingView, didTapShift: Void)
    func ringView(_ ringView: RingView, didTapReturn: Void)
    func ringView(_ ringView: RingView, didMoveCursorLeft: Void)
    func ringView(_ ringView: RingView, didMoveCursorRight: Void)
    func ringView(_ ringView: RingView, didDeleteWord: Void)
    func ringView(_ ringView: RingView, didTapPunctuation character: Character)
    func ringView(_ ringView: RingView, didTapPrediction word: String)
}

class RingView: UIView {

    weak var delegate: RingViewDelegate?

    // MARK: - Layout state

    private(set) var slots: [KeySlot] = []
    private var letterSlots: [KeySlot] = []
    private var symbolSlots: [KeySlot] = []
    private(set) var isSymbolMode = false
    private var center_: CGPoint = .zero
    private var scale: CGFloat = 1.0

    // MARK: - Layers

    private let innerRingArc = CAShapeLayer()
    private let outerRingArc = CAShapeLayer()
    private let backspaceZone = CAShapeLayer()
    private let spaceZone = CAShapeLayer()
    private let centerZone = CAShapeLayer()
    private let backspaceLabel = CATextLayer()
    private let spaceLabel = CATextLayer()
    private var keyCapLayers: [KeyCapLayer] = []
    let swipeTrail = SwipeTrailLayer()

    // MARK: - Auxiliary buttons (two columns: controls far-left, punctuation near-ring)

    private let shiftButton = UIButton(type: .system)
    private let numbersButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)

    private let periodButton = UIButton(type: .system)
    private let commaButton = UIButton(type: .system)
    private let apostropheButton = UIButton(type: .system)
    private let questionButton = UIButton(type: .system)
    private let exclamationButton = UIButton(type: .system)

    // MARK: - Prediction bar

    private let predictionBar = UIView()
    private var predictionButtons: [UIButton] = []
    static let predictionBarHeight: CGFloat = 36.0

    // MARK: - Theme colors

    private static let bgColor = UIColor.black
    private static let dimColor = UIColor(white: 0.15, alpha: 1.0)
    private static let subtleStroke = UIColor(white: 0.25, alpha: 1.0)
    private static let labelColor = UIColor(white: 0.5, alpha: 1.0)
    private static let glowColor = SwipeTrailLayer.glowColor

    // MARK: - Input handling

    private lazy var touchRouter = TouchRouter(ringView: self)

    // MARK: - Constants

    static let centerTapRadius: CGFloat = 30.0
    static let tapProximityThreshold: CGFloat = 44.0
    static let swipeProximityThreshold: CGFloat = 26.0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.bgColor
        setupLayers()
        setupButtons()
        setupPredictionBar()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Configuration

    func configure(viewSize: CGSize) {
        let layout = RingLayoutConfig.computeLayout(viewSize: viewSize)
        center_ = CGPoint(x: layout.center.x,
                          y: layout.center.y + Self.predictionBarHeight / 2.0)
        scale = layout.scale

        letterSlots = RingLayoutConfig.makeSlots()
        RingLayoutConfig.applyScreenPositions(slots: &letterSlots, center: center_, scale: scale)

        symbolSlots = RingLayoutConfig.makeSymbolSlots()
        RingLayoutConfig.applyScreenPositions(slots: &symbolSlots, center: center_, scale: scale)

        slots = isSymbolMode ? symbolSlots : letterSlots
        rebuildLayers()
    }

    // MARK: - Dark mode (no-op in pure black mode, but keep for future)

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            refreshAllColors()
        }
    }

    private func refreshAllColors() {
        innerRingArc.strokeColor = Self.subtleStroke.cgColor
        outerRingArc.strokeColor = Self.subtleStroke.cgColor
        backspaceZone.fillColor = UIColor.systemRed.withAlphaComponent(0.08).cgColor
        backspaceZone.strokeColor = Self.subtleStroke.withAlphaComponent(0.3).cgColor
        spaceZone.fillColor = Self.glowColor.withAlphaComponent(0.04).cgColor
        spaceZone.strokeColor = Self.subtleStroke.withAlphaComponent(0.3).cgColor
        backspaceLabel.foregroundColor = Self.labelColor.cgColor
        spaceLabel.foregroundColor = Self.labelColor.cgColor
        centerZone.fillColor = Self.dimColor.cgColor
        centerZone.strokeColor = Self.subtleStroke.cgColor
        keyCapLayers.forEach { $0.refreshColors() }
    }

    // MARK: - Shift state

    func updateShiftAppearance(isShifted: Bool) {
        let symbolName = isShifted ? "shift.fill" : "shift"
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        shiftButton.setImage(UIImage(systemName: symbolName, withConfiguration: config), for: .normal)
        shiftButton.tintColor = isShifted ? Self.glowColor : .white
    }

    // MARK: - Layer setup

    private func setupLayers() {
        for l in [innerRingArc, outerRingArc, backspaceZone, spaceZone, centerZone] {
            layer.addSublayer(l)
        }
        layer.addSublayer(backspaceLabel)
        layer.addSublayer(spaceLabel)
        layer.addSublayer(swipeTrail)
    }

    private func setupButtons() {
        // Control buttons (SF Symbol icons)
        let controlButtons: [(UIButton, String, Selector)] = [
            (shiftButton, "shift", #selector(shiftTapped)),
            (numbersButton, "textformat.123", #selector(numbersTapped)),
            (returnButton, "return.left", #selector(returnTapped)),
        ]

        for (btn, symbolName, action) in controlButtons {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            btn.setImage(UIImage(systemName: symbolName, withConfiguration: config), for: .normal)
            btn.setTitle(nil, for: .normal)
            btn.tintColor = .white
            btn.backgroundColor = Self.dimColor
            btn.layer.cornerRadius = 10
            btn.addTarget(self, action: action, for: .touchUpInside)
            addSubview(btn)
        }

        // Punctuation buttons (text labels)
        let punctButtons: [(UIButton, String)] = [
            (periodButton, "."),
            (commaButton, ","),
            (apostropheButton, "'"),
            (questionButton, "?"),
            (exclamationButton, "!"),
        ]

        for (btn, label) in punctButtons {
            btn.setTitle(label, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = Self.dimColor
            btn.layer.cornerRadius = 8
            btn.addTarget(self, action: #selector(punctuationTapped(_:)), for: .touchUpInside)
            addSubview(btn)
        }
    }

    private func setupPredictionBar() {
        predictionBar.backgroundColor = .clear
        addSubview(predictionBar)

        for i in 0..<3 {
            let btn = UIButton(type: .system)
            btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = Self.dimColor
            btn.layer.cornerRadius = 8
            btn.tag = i
            btn.addTarget(self, action: #selector(predictionTapped(_:)), for: .touchUpInside)
            predictionBar.addSubview(btn)
            predictionButtons.append(btn)
        }
    }

    private func rebuildLayers() {
        keyCapLayers.forEach { $0.removeFromSuperlayer() }
        keyCapLayers.removeAll()

        drawRingArcs()
        drawGapZones()
        drawCenterZone()

        for slot in slots {
            let keyCap = KeyCapLayer(slot: slot)
            keyCap.updateWedge(center: center_, scale: scale)
            layer.addSublayer(keyCap)
            keyCapLayers.append(keyCap)
        }

        swipeTrail.removeFromSuperlayer()
        layer.addSublayer(swipeTrail)

        layoutButtons()
        layoutPredictionBar()
    }

    // MARK: - Drawing

    private func drawRingArcs() {
        // Draw arcs in two segments, breaking at the left gap (backspace zone)
        // Segment 1: 18° → 162° (upper, right gap to left gap)
        // Segment 2: 198° → 342° (lower, left gap to right gap)
        let seg1Start = -RingLayoutConfig.arcStartDeg * .pi / 180.0            // -18°
        let seg1End = -RingLayoutConfig.arcEndDeg * .pi / 180.0                // -162°
        let seg2Start = -(RingLayoutConfig.leftGapAngle + RingLayoutConfig.gapWidthDeg / 2.0) * .pi / 180.0  // -198°
        let seg2End = -(360.0 - RingLayoutConfig.gapWidthDeg / 2.0) * .pi / 180.0  // -342°

        for (ringLayer, radius) in [(innerRingArc, RingLayoutConfig.innerRadius),
                                     (outerRingArc, RingLayoutConfig.outerRadius)] {
            let r = radius * scale
            let path = UIBezierPath()
            path.addArc(withCenter: center_, radius: r,
                        startAngle: seg1Start, endAngle: seg1End, clockwise: false)
            path.move(to: CGPoint(x: center_.x + r * cos(seg2Start),
                                   y: center_.y + r * sin(seg2Start)))
            path.addArc(withCenter: center_, radius: r,
                        startAngle: seg2Start, endAngle: seg2End, clockwise: false)
            ringLayer.path = path.cgPath
            ringLayer.fillColor = nil
            ringLayer.strokeColor = Self.subtleStroke.cgColor
            ringLayer.lineWidth = 0.5
            ringLayer.lineDashPattern = [4, 6]
        }
    }

    private func drawGapZones() {
        drawGapWedge(layer: backspaceZone,
                     gapCenter: RingLayoutConfig.leftGapAngle,
                     fillColor: UIColor.systemRed.withAlphaComponent(0.08).cgColor)
        positionGapLabel(backspaceLabel, text: "\u{232B}",
                         gapCenter: RingLayoutConfig.leftGapAngle, fontSize: 20)

        drawGapWedge(layer: spaceZone,
                     gapCenter: RingLayoutConfig.rightGapAngle,
                     fillColor: Self.glowColor.withAlphaComponent(0.04).cgColor)
        positionGapLabel(spaceLabel, text: "[_]",
                         gapCenter: RingLayoutConfig.rightGapAngle, fontSize: 14)
    }

    private func drawGapWedge(layer wedgeLayer: CAShapeLayer,
                              gapCenter: CGFloat, fillColor: CGColor) {
        let halfGap = RingLayoutConfig.gapWidthDeg / 2.0
        let startRad = CGFloat(-(gapCenter - halfGap)) * .pi / 180.0
        let endRad = CGFloat(-(gapCenter + halfGap)) * .pi / 180.0

        let rInner = RingLayoutConfig.outerWedgeRMin * scale   // midpoint (1.6)
        let rOuter = RingLayoutConfig.outerWedgeRMax * scale  // outer edge (2.35)

        let path = UIBezierPath()
        path.addArc(withCenter: center_, radius: rOuter,
                    startAngle: startRad, endAngle: endRad, clockwise: false)
        path.addArc(withCenter: center_, radius: rInner,
                    startAngle: endRad, endAngle: startRad, clockwise: true)
        path.close()

        wedgeLayer.path = path.cgPath
        wedgeLayer.fillColor = fillColor
        wedgeLayer.strokeColor = Self.subtleStroke.withAlphaComponent(0.3).cgColor
        wedgeLayer.lineWidth = 0.5
    }

    private func positionGapLabel(_ textLayer: CATextLayer, text: String,
                                  gapCenter: CGFloat, fontSize: CGFloat) {
        let midRadius = (RingLayoutConfig.outerWedgeRMin + RingLayoutConfig.outerWedgeRMax) / 2.0 * scale
        let angleRad = -gapCenter * .pi / 180.0
        let cx = center_.x + midRadius * cos(angleRad)
        let cy = center_.y + midRadius * sin(angleRad)

        let size = CGSize(width: 60, height: 24)
        textLayer.frame = CGRect(x: cx - size.width / 2, y: cy - size.height / 2,
                                 width: size.width, height: size.height)
        textLayer.string = text
        textLayer.fontSize = fontSize
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = Self.labelColor.cgColor
        textLayer.contentsScale = UIScreen.main.scale
    }

    private func drawCenterZone() {
        let r = Self.centerTapRadius
        let path = UIBezierPath(ovalIn: CGRect(x: center_.x - r, y: center_.y - r,
                                               width: r * 2, height: r * 2))
        centerZone.path = path.cgPath
        centerZone.fillColor = Self.dimColor.cgColor
        centerZone.strokeColor = Self.subtleStroke.cgColor
        centerZone.lineWidth = 0.5
    }

    private func layoutButtons() {
        let controlSize: CGFloat = 38
        let punctSize: CGFloat = 34
        let spacing: CGFloat = 5
        let colGap: CGFloat = 4
        let outerEdge = RingLayoutConfig.outerWedgeRMax * scale

        // Near-ring column (punctuation): just left of the ring
        let punctX = max(controlSize + colGap + 4,
                         center_.x - outerEdge - punctSize - 2)

        // Far-left column (controls): left of punctuation
        let controlX = max(4, punctX - controlSize - colGap)

        // Punctuation column: 5 buttons centered vertically
        let punctButtons = [periodButton, commaButton, apostropheButton,
                            questionButton, exclamationButton]
        let punctHeight = CGFloat(punctButtons.count) * punctSize
            + CGFloat(punctButtons.count - 1) * spacing
        let punctTopY = center_.y - punctHeight / 2.0

        for (i, btn) in punctButtons.enumerated() {
            let y = punctTopY + CGFloat(i) * (punctSize + spacing)
            btn.frame = CGRect(x: punctX, y: y, width: punctSize, height: punctSize)
            btn.frame.origin.y = max(Self.predictionBarHeight + 4,
                                     min(btn.frame.origin.y, bounds.height - punctSize - 4))
        }

        // Control column: 3 buttons centered vertically
        let controlButtons = [shiftButton, numbersButton, returnButton]
        let controlHeight = CGFloat(controlButtons.count) * controlSize
            + CGFloat(controlButtons.count - 1) * spacing
        let controlTopY = center_.y - controlHeight / 2.0

        for (i, btn) in controlButtons.enumerated() {
            let y = controlTopY + CGFloat(i) * (controlSize + spacing)
            btn.frame = CGRect(x: controlX, y: y, width: controlSize, height: controlSize)
            btn.frame.origin.y = max(Self.predictionBarHeight + 4,
                                     min(btn.frame.origin.y, bounds.height - controlSize - 4))
        }
    }

    private func layoutPredictionBar() {
        let barH = Self.predictionBarHeight
        predictionBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: barH)

        let padding: CGFloat = 8
        let spacing: CGFloat = 6
        let totalSpacing = padding * 2 + spacing * 2
        let btnW = (bounds.width - totalSpacing) / 3.0
        let btnH: CGFloat = barH - 8

        for (i, btn) in predictionButtons.enumerated() {
            btn.frame = CGRect(x: padding + CGFloat(i) * (btnW + spacing),
                               y: 4,
                               width: btnW,
                               height: btnH)
        }
    }

    // MARK: - Prediction bar

    func updatePredictions(_ words: [String]) {
        for (i, btn) in predictionButtons.enumerated() {
            if i < words.count {
                btn.setTitle(words[i], for: .normal)
                btn.isHidden = false
            } else {
                btn.setTitle(nil, for: .normal)
                btn.isHidden = true
            }
        }
    }

    // MARK: - Key highlighting

    func highlightKey(at index: Int) {
        guard index >= 0, index < keyCapLayers.count else { return }
        keyCapLayers[index].setHighlighted(true)
    }

    func unhighlightAllKeys() {
        keyCapLayers.forEach { $0.setHighlighted(false) }
    }

    // MARK: - Button actions

    @objc private func shiftTapped() {
        delegate?.ringView(self, didTapShift: ())
    }

    @objc private func numbersTapped() {
        toggleSymbolMode()
    }

    private func toggleSymbolMode() {
        isSymbolMode.toggle()
        slots = isSymbolMode ? symbolSlots : letterSlots
        rebuildLayers()
        updateSymbolButtonAppearance()
    }

    private func updateSymbolButtonAppearance() {
        if isSymbolMode {
            numbersButton.setImage(nil, for: .normal)
            numbersButton.setTitle("ABC", for: .normal)
            numbersButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            numbersButton.setTitleColor(.white, for: .normal)
        } else {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            numbersButton.setImage(UIImage(systemName: "textformat.123", withConfiguration: config), for: .normal)
            numbersButton.setTitle(nil, for: .normal)
        }
    }

    @objc private func returnTapped() {
        delegate?.ringView(self, didTapReturn: ())
    }

    @objc private func punctuationTapped(_ sender: UIButton) {
        guard let text = sender.title(for: .normal), let char = text.first else { return }
        delegate?.ringView(self, didTapPunctuation: char)
    }

    @objc private func predictionTapped(_ sender: UIButton) {
        guard let word = sender.title(for: .normal), !word.isEmpty else { return }
        delegate?.ringView(self, didTapPrediction: word)
    }

    // MARK: - Touch handling (delegated to TouchRouter)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchRouter.touchBegan(touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchRouter.touchMoved(touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchRouter.touchEnded(touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchRouter.touchCancelled()
    }
}


######################################################################
# TouchRouter.swift — State just before keyboard switch prevention (line 666)
# Last full write: line 288, then 9 edits
######################################################################

import UIKit

/// Classifies touches and routes them to the appropriate handler.
class TouchRouter {

    enum TouchMode {
        case none
        case centerTap
        case keyTap(KeySlot)
        case ringSwipe
        case backspace
        case spaceZone        // right gap: tap = space
    }

    private weak var ringView: RingView?
    private var mode: TouchMode = .none
    private var startPoint: CGPoint = .zero
    private var swipeTracker: SwipeTracker?

    /// Movement threshold to transition from tap to swipe
    private let swipeThreshold: CGFloat = 15.0

    init(ringView: RingView) {
        self.ringView = ringView
    }

    // MARK: - Touch events

    func touchBegan(_ point: CGPoint) {
        guard let ringView = ringView else { return }
        startPoint = point

        let slots = ringView.slots
        let center = CGPoint(
            x: ringView.bounds.width / 2.0,
            y: ringView.bounds.height / 2.0
        )

        let distFromCenter = GeometryHelpers.distanceFromCenter(point, center: center)

        // Check center zone — tap=space, but can transition to swipe on drag
        if distFromCenter < RingView.centerTapRadius {
            mode = .centerTap
            // Pre-arm swipe tracker so center-drag-to-swipe works
            swipeTracker = SwipeTracker(slots: slots)
            swipeTracker?.ringCenter = center
            swipeTracker?.begin(at: point, initialSlot: nil)
            return
        }

        // Check gap zones — only in the outer ring radial range
        let angle = GeometryHelpers.angleDeg(from: center, to: point)
        let scale = ringView.bounds.height > 0
            ? (min(ringView.bounds.width, ringView.bounds.height) / 2.0 - 30.0)
              / (RingLayoutConfig.outerRadius + 0.3)
            : 1.0
        let outerRingMinR = RingLayoutConfig.outerWedgeRMin * scale

        // Only trigger gap zones when touch is in outer ring area
        if distFromCenter >= outerRingMinR {
            // Backspace zone (left gap around 180°)
            if GeometryHelpers.angleInGap(angle,
                                           gapCenter: RingLayoutConfig.leftGapAngle,
                                           gapWidth: RingLayoutConfig.gapWidthDeg) {
                mode = .backspace
                return
            }

            // Space zone (right gap around 0°) — tap=space
            if GeometryHelpers.angleInGap(angle,
                                           gapCenter: RingLayoutConfig.rightGapAngle,
                                           gapWidth: RingLayoutConfig.gapWidthDeg) {
                mode = .spaceZone
                return
            }
        }

        // Check nearest key (frequency-weighted, generous tap threshold)
        if let (nearest, dist) = GeometryHelpers.weightedNearestSlot(
            to: point, in: slots, maxDist: RingView.tapProximityThreshold),
           dist < RingView.tapProximityThreshold {
            mode = .keyTap(nearest)
            ringView.highlightKey(at: nearest.index)

            // Start swipe tracker in case this becomes a swipe
            swipeTracker = SwipeTracker(slots: slots)
            swipeTracker?.ringCenter = center
            swipeTracker?.begin(at: point, initialSlot: nearest)
            ringView.swipeTrail.beginTrail(at: point)
            return
        }

        // Anywhere else — start as potential swipe
        swipeTracker = SwipeTracker(slots: slots)
        swipeTracker?.ringCenter = center
        swipeTracker?.begin(at: point, initialSlot: nil)
        ringView.swipeTrail.beginTrail(at: point)
        mode = .ringSwipe
    }

    func touchMoved(_ point: CGPoint) {
        guard let ringView = ringView else { return }

        switch mode {
        case .centerTap:
            let moved = GeometryHelpers.distance(startPoint, point)
            if moved > swipeThreshold {
                // Transition center tap → swipe
                mode = .ringSwipe
                ringView.swipeTrail.beginTrail(at: startPoint)
                if let tracker = swipeTracker {
                    tracker.addSample(point)
                    ringView.swipeTrail.addPoint(point)
                }
            }

        case .keyTap:
            let moved = GeometryHelpers.distance(startPoint, point)
            if moved > swipeThreshold {
                mode = .ringSwipe
                ringView.unhighlightAllKeys()
            }
            if let tracker = swipeTracker {
                tracker.addSample(point)
                ringView.swipeTrail.addPoint(point)
                ringView.unhighlightAllKeys()
                if let current = tracker.currentSlot {
                    ringView.highlightKey(at: current.index)
                }
            }

        case .ringSwipe:
            if let tracker = swipeTracker {
                tracker.addSample(point)
                ringView.swipeTrail.addPoint(point)
                ringView.unhighlightAllKeys()
                if let current = tracker.currentSlot {
                    ringView.highlightKey(at: current.index)
                }
            }

        default:
            break
        }
    }

    func touchEnded(_ point: CGPoint) {
        guard let ringView = ringView else { return }

        defer {
            cleanup()
        }

        switch mode {
        case .centerTap:
            ringView.delegate?.ringView(ringView, didTapSpace: ())

        case .keyTap(let slot):
            let moved = GeometryHelpers.distance(startPoint, point)
            if moved <= swipeThreshold {
                ringView.delegate?.ringView(ringView, didTapLetter: slot.letter)
            } else {
                finalizeSwipe()
            }

        case .ringSwipe:
            finalizeSwipe()

        case .backspace:
            let moved = GeometryHelpers.distance(startPoint, point)
            let swipedLeft = point.x < startPoint.x
            if moved > swipeThreshold && swipedLeft {
                ringView.delegate?.ringView(ringView, didDeleteWord: ())
            } else if moved <= swipeThreshold {
                ringView.delegate?.ringView(ringView, didTapBackspace: ())
            }
            // Swiped right from backspace zone — ignore

        case .spaceZone:
            ringView.delegate?.ringView(ringView, didTapSpace: ())

        case .none:
            break
        }
    }

    func touchCancelled() {
        cleanup()
    }

    // MARK: - Private

    private func finalizeSwipe() {
        guard let ringView = ringView,
              let tracker = swipeTracker else { return }
        let visitedSlots = tracker.finalize()
        if !visitedSlots.isEmpty {
            ringView.delegate?.ringView(ringView, didSwipeWord: visitedSlots)
        }
    }

    private func cleanup() {
        ringView?.unhighlightAllKeys()
        ringView?.swipeTrail.clearTrail()
        swipeTracker = nil
        mode = .none
    }
}
# Current Status

Every swipe triggers keyboard switch. Stripping ALL prevention code didn't help. The simple disableConflictingSystemGestures (only UISwipe+UIPan) didn't help either. The pre-switch-state.txt shows the reconstructed code from before the nuclear keyboard switch prevention was added. The issue may have been introduced during an earlier edit (perhaps the arc buttons, cursor changes, or third ring removal). Need to diff the pre-switch-state.txt TouchRouter/RingView against current to find what changed.
