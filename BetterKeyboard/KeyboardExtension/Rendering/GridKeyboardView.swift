import UIKit

/// A traditional ortholinear grid keyboard layout (QWERTY, Dvorak, Workman, Coyote).
/// Conforms to KeyboardLayoutView so the VC can swap it in/out with the ring layout.
class GridKeyboardView: UIView, KeyboardLayoutView {

    weak var delegate: KeyboardLayoutDelegate?

    var preferredHeight: CGFloat { 260 }

    // MARK: - Layout state

    enum InputMode {
        case letters
        case symbols1
        case symbols2
    }

    private let layoutName: GridLayoutName
    private(set) var slots: [KeySlot] = []
    private var letterSlots: [KeySlot] = []
    private var symbolSlots1: [KeySlot] = []
    private var symbolSlots2: [KeySlot] = []
    private(set) var inputMode: InputMode = .letters

    // MARK: - Layers

    private var keyCapLayers: [GridKeyCapLayer] = []
    let swipeTrail = SwipeTrailLayer()

    // MARK: - Special key buttons

    private let shiftButton = UIButton(type: .system)
    private let backspaceButton = UIButton(type: .system)
    private let symbolToggleButton = UIButton(type: .system)  // "123" / "ABC"
    private let layoutCycleButton = UIButton(type: .system)    // switch layouts
    private let commaButton = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let periodButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)

    // MARK: - Prediction bar

    private var predictionButtons: [UIButton] = []
    private var predictionDividers: [UIView] = []
    private var predictions: [String] = []

    // MARK: - Top bar buttons

    private let dismissButton = UIButton(type: .system)
    private let layoutNameLabel = UILabel()

    // MARK: - Input

    private lazy var touchRouter = GridTouchRouter(gridView: self)

    // MARK: - Backspace repeat

    private var backspaceTimer: Timer?

    // MARK: - Init

    init(layout: GridLayoutName) {
        self.layoutName = layout
        super.init(frame: .zero)
        backgroundColor = KeyboardTheme.current.backgroundColor
        setupButtons()
        layer.addSublayer(swipeTrail)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - KeyboardLayoutView conformance

    func configure(viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        letterSlots = GridLayoutConfig.makeSlots(layout: layoutName, viewSize: viewSize)
        symbolSlots1 = GridLayoutConfig.makeSymbolSlots(set: 1, viewSize: viewSize)
        symbolSlots2 = GridLayoutConfig.makeSymbolSlots(set: 2, viewSize: viewSize)

        switch inputMode {
        case .letters:  slots = letterSlots
        case .symbols1: slots = symbolSlots1
        case .symbols2: slots = symbolSlots2
        }

        rebuildKeyLayers()
        layoutSpecialKeys(viewSize: viewSize)
        layoutPredictionBar(viewSize: viewSize)
    }

    func updatePredictions(_ suggestions: [String]) {
        predictions = suggestions
        for (i, btn) in predictionButtons.enumerated() {
            if i < suggestions.count {
                btn.setTitle(suggestions[i], for: .normal)
                btn.isHidden = false
            } else {
                btn.setTitle(nil, for: .normal)
                btn.isHidden = true
            }
        }
        predictionDividers[0].isHidden = suggestions.count < 2
        predictionDividers[1].isHidden = suggestions.count < 3
    }

    func updateShiftAppearance(isShifted: Bool, isCapsLocked: Bool) {
        let theme = KeyboardTheme.current
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        shiftButton.setTitle(nil, for: .normal)

        if isCapsLocked {
            shiftButton.setImage(UIImage(systemName: "capslock.fill")?.withConfiguration(config), for: .normal)
            shiftButton.tintColor = theme.buttonTextColor
            shiftButton.backgroundColor = theme.glowColor.withAlphaComponent(0.6)
        } else {
            shiftButton.setImage(UIImage(systemName: "shift")?.withConfiguration(config), for: .normal)
            shiftButton.tintColor = theme.buttonTextColor
            shiftButton.backgroundColor = isShifted
                ? theme.glowColor.withAlphaComponent(0.3) : theme.buttonFillColor
        }

    }

    func reapplyTheme() {
        let theme = KeyboardTheme.current
        backgroundColor = theme.backgroundColor
        swipeTrail.applyTheme()

        rebuildKeyLayers()

        let allButtons = [shiftButton, backspaceButton, symbolToggleButton,
                          commaButton, spaceButton, periodButton, returnButton]
        for btn in allButtons {
            applyButtonStyle(btn)
        }

        layoutCycleButton.tintColor = theme.buttonTextColor
        dismissButton.tintColor = theme.buttonTextColor
        layoutNameLabel.textColor = theme.buttonTextColor.withAlphaComponent(0.4)

        for btn in predictionButtons {
            btn.setTitleColor(theme.buttonTextColor, for: .normal)
        }

        updateSymbolToggleLabel()
    }

    // MARK: - Key highlighting (called by GridTouchRouter)

    func highlightKey(at index: Int) {
        guard index >= 0, index < keyCapLayers.count else { return }
        keyCapLayers[index].setHighlighted(true)
    }

    func unhighlightAllKeys() {
        keyCapLayers.forEach { $0.setHighlighted(false) }
    }

    // MARK: - Layer management

    private func rebuildKeyLayers() {
        keyCapLayers.forEach { $0.removeFromSuperlayer() }
        keyCapLayers.removeAll()

        for slot in slots {
            let keyCap = GridKeyCapLayer(slot: slot)
            keyCap.updateLayout()
            layer.addSublayer(keyCap)
            keyCapLayers.append(keyCap)
        }

        // Keep swipe trail on top
        swipeTrail.removeFromSuperlayer()
        layer.addSublayer(swipeTrail)
    }

    // MARK: - Button setup

    private func setupButtons() {
        let theme = KeyboardTheme.current

        // Shift
        let shiftConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        shiftButton.setImage(UIImage(systemName: "shift")?.withConfiguration(shiftConfig), for: .normal)
        shiftButton.tintColor = theme.buttonTextColor
        shiftButton.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
        applyButtonStyle(shiftButton)
        addSubview(shiftButton)

        // Backspace
        let bsConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        backspaceButton.setImage(UIImage(systemName: "delete.left")?.withConfiguration(bsConfig), for: .normal)
        backspaceButton.tintColor = theme.buttonTextColor
        backspaceButton.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        backspaceButton.addTarget(self, action: #selector(backspaceDown), for: .touchDown)
        backspaceButton.addTarget(self, action: #selector(backspaceUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        applyButtonStyle(backspaceButton)
        addSubview(backspaceButton)

        // Symbol toggle (123 / ABC)
        symbolToggleButton.setTitle("123", for: .normal)
        symbolToggleButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        symbolToggleButton.addTarget(self, action: #selector(symbolToggleTapped), for: .touchUpInside)
        applyButtonStyle(symbolToggleButton)
        addSubview(symbolToggleButton)

        // Layout cycle (top-left, unstyled icon — matches ring view position)
        let cycleConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        layoutCycleButton.setImage(UIImage(systemName: "keyboard")?.withConfiguration(cycleConfig), for: .normal)
        layoutCycleButton.tintColor = theme.buttonTextColor
        layoutCycleButton.addTarget(self, action: #selector(layoutCycleTapped), for: .touchUpInside)
        addSubview(layoutCycleButton)

        // Comma
        commaButton.setTitle(",", for: .normal)
        commaButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .regular)
        commaButton.addTarget(self, action: #selector(commaTapped), for: .touchUpInside)
        applyButtonStyle(commaButton)
        addSubview(commaButton)

        // Space bar
        spaceButton.setTitle("space", for: .normal)
        spaceButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        spaceButton.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        applyButtonStyle(spaceButton)
        addSubview(spaceButton)

        // Period
        periodButton.setTitle(".", for: .normal)
        periodButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .regular)
        periodButton.addTarget(self, action: #selector(periodTapped), for: .touchUpInside)
        applyButtonStyle(periodButton)
        addSubview(periodButton)

        // Return
        returnButton.setTitle("\u{21B5}", for: .normal)
        returnButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        returnButton.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        applyButtonStyle(returnButton)
        addSubview(returnButton)

        // Dismiss keyboard (top-right)
        let dismissConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        dismissButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down")?.withConfiguration(dismissConfig), for: .normal)
        dismissButton.tintColor = theme.buttonTextColor
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        addSubview(dismissButton)

        // Layout name label (temporary — for distinguishing layouts during development)
        layoutNameLabel.text = layoutName.rawValue
        layoutNameLabel.font = .systemFont(ofSize: 9, weight: .medium)
        layoutNameLabel.textColor = theme.buttonTextColor.withAlphaComponent(0.4)
        layoutNameLabel.textAlignment = .center
        addSubview(layoutNameLabel)

        // Prediction buttons — 3 slots in top strip
        for i in 0..<3 {
            let btn = UIButton(type: .system)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            btn.setTitleColor(theme.buttonTextColor, for: .normal)
            btn.tag = i
            btn.isHidden = true
            btn.addTarget(self, action: #selector(predictionTapped(_:)), for: .touchUpInside)
            addSubview(btn)
            predictionButtons.append(btn)
        }

        // Hairline dividers between prediction buttons
        for _ in 0..<2 {
            let div = UIView()
            div.backgroundColor = UIColor(white: 0.3, alpha: 0.5)
            div.isHidden = true
            addSubview(div)
            predictionDividers.append(div)
        }
    }

    private func applyButtonStyle(_ btn: UIButton) {
        let theme = KeyboardTheme.current
        btn.backgroundColor = theme.buttonFillColor
        btn.setTitleColor(theme.buttonTextColor, for: .normal)
        btn.layer.cornerRadius = theme.buttonCornerRadius
        if let borderColor = theme.buttonBorderColor {
            btn.layer.borderColor = borderColor.cgColor
            btn.layer.borderWidth = theme.buttonBorderWidth
        } else {
            btn.layer.borderWidth = 0
        }
    }

    // MARK: - Layout special keys

    private func layoutSpecialKeys(viewSize: CGSize) {
        let rows = currentRows()
        let sp = GridLayoutConfig.keySpacing
        let keyH = GridLayoutConfig.baseKeyHeight

        // Compute key width from the widest row (same formula as GridLayoutConfig.buildSlots)
        let maxCols = rows.map(\.count).max() ?? 10
        let totalSpacing = sp * CGFloat(maxCols + 1)
        let keyW = min(GridLayoutConfig.baseKeyWidth, (viewSize.width - totalSpacing) / CGFloat(maxCols))

        // Shift and backspace sit on the same row as the last letter row,
        // sized relative to THAT row's letter count so they fill the available space.
        let modY = GridLayoutConfig.modifierRowY(letterRowCount: rows.count, viewSize: viewSize)
        let lastRowCount = rows.last?.count ?? 7
        let lastRowWidth = CGFloat(lastRowCount) * keyW + CGFloat(max(0, lastRowCount - 1)) * sp
        let lastRowLeft = (viewSize.width - lastRowWidth) / 2.0
        let lastRowRight = lastRowLeft + lastRowWidth

        // Shift: left of last row's letters
        let shiftWidth = max(keyW, lastRowLeft - sp * 2)
        shiftButton.frame = CGRect(x: sp, y: modY - keyH / 2,
                                    width: shiftWidth, height: keyH)

        // Backspace: right of last row's letters
        let bsWidth = max(keyW, viewSize.width - lastRowRight - sp * 2)
        backspaceButton.frame = CGRect(x: lastRowRight + sp, y: modY - keyH / 2,
                                        width: bsWidth, height: keyH)

        // Bottom row: [123] [,] [   space   ] [.] [↵]
        // (layout cycle button is in the top bar, not here)
        let bottomY = GridLayoutConfig.bottomRowY(letterRowCount: rows.count, viewSize: viewSize)
        let bottomH = GridLayoutConfig.bottomRowHeight
        let smallW: CGFloat = 38
        let spaceW = viewSize.width - smallW * 4 - sp * 6  // space gets remaining width

        var x: CGFloat = sp
        symbolToggleButton.frame = CGRect(x: x, y: bottomY - bottomH / 2, width: smallW, height: bottomH)
        x += smallW + sp

        commaButton.frame = CGRect(x: x, y: bottomY - bottomH / 2, width: smallW, height: bottomH)
        x += smallW + sp

        spaceButton.frame = CGRect(x: x, y: bottomY - bottomH / 2, width: spaceW, height: bottomH)
        x += spaceW + sp

        periodButton.frame = CGRect(x: x, y: bottomY - bottomH / 2, width: smallW, height: bottomH)
        x += smallW + sp

        returnButton.frame = CGRect(x: x, y: bottomY - bottomH / 2, width: smallW, height: bottomH)
    }

    private func layoutPredictionBar(viewSize: CGSize) {
        // Top bar: [cycle] [predictions...] [layout name] [dismiss]
        // Mirrors the ring view's top strip layout
        let predH: CGFloat = 26
        let predY: CGFloat = 4

        layoutCycleButton.frame = CGRect(x: 8, y: predY, width: 30, height: 30)
        dismissButton.frame = CGRect(x: viewSize.width - 38, y: predY, width: 30, height: 30)

        // Tiny layout name label just left of dismiss
        let labelW: CGFloat = 50
        layoutNameLabel.frame = CGRect(x: dismissButton.frame.minX - labelW - 2, y: predY,
                                        width: labelW, height: 30)

        // Predictions fill the space between cycle button and layout label
        let predLeft = layoutCycleButton.frame.maxX + 4
        let predRight = layoutNameLabel.frame.minX - 4
        let predWidth = predRight - predLeft
        let btnWidth = predWidth / 3.0

        // Display order: [2nd, best, 3rd] — best in center for easy thumb reach
        let displayOrder = [1, 0, 2]
        for (displaySlot, btnIdx) in displayOrder.enumerated() {
            let x = predLeft + CGFloat(displaySlot) * btnWidth
            predictionButtons[btnIdx].frame = CGRect(x: x, y: predY, width: btnWidth, height: predH)
        }

        // Dividers between prediction slots
        for (i, div) in predictionDividers.enumerated() {
            let x = predLeft + CGFloat(i + 1) * btnWidth
            div.frame = CGRect(x: x - 0.25, y: predY + 4, width: 0.5, height: predH - 8)
        }
    }

    /// Returns the current row definitions (letters or symbols).
    private func currentRows() -> [String] {
        switch inputMode {
        case .letters:  return GridLayoutConfig.rows(for: layoutName)
        case .symbols1: return GridLayoutConfig.symbolRows1
        case .symbols2: return GridLayoutConfig.symbolRows2
        }
    }

    // MARK: - Button actions

    @objc private func shiftTapped() {
        if inputMode == .letters {
            delegate?.keyboardLayout(self, didTapShift: ())
        } else {
            toggleSymbolSet()
        }
    }

    @objc private func backspaceTapped() {
        delegate?.keyboardLayout(self, didTapBackspace: ())
    }

    @objc private func backspaceDown() {
        // Start repeat timer after initial delay
        backspaceTimer?.invalidate()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.keyboardLayout(self, didTapBackspace: ())
            }
        }
    }

    @objc private func backspaceUp() {
        backspaceTimer?.invalidate()
        backspaceTimer = nil
    }

    @objc private func symbolToggleTapped() {
        toggleSymbolMode()
    }

    @objc private func layoutCycleTapped() {
        delegate?.keyboardLayout(self, didRequestLayoutCycle: ())
    }

    @objc private func commaTapped() {
        delegate?.keyboardLayout(self, didTapPunctuation: ",")
    }

    @objc private func spaceTapped() {
        delegate?.keyboardLayout(self, didTapSpace: ())
    }

    @objc private func periodTapped() {
        delegate?.keyboardLayout(self, didTapPunctuation: ".")
    }

    @objc private func returnTapped() {
        delegate?.keyboardLayout(self, didTapReturn: ())
    }

    @objc private func dismissTapped() {
        delegate?.keyboardLayout(self, didTapDismiss: ())
    }

    @objc private func predictionTapped(_ sender: UIButton) {
        guard sender.tag < predictions.count else { return }
        delegate?.keyboardLayout(self, didSelectPrediction: predictions[sender.tag])
    }

    // MARK: - Symbol mode

    private func toggleSymbolMode() {
        if inputMode == .letters {
            inputMode = .symbols1
            slots = symbolSlots1
        } else {
            inputMode = .letters
            slots = letterSlots
        }
        rebuildKeyLayers()
        layoutSpecialKeys(viewSize: bounds.size)
        updateSymbolToggleLabel()
        updateShiftForSymbolMode()
    }

    private func toggleSymbolSet() {
        if inputMode == .symbols1 {
            inputMode = .symbols2
            slots = symbolSlots2
        } else {
            inputMode = .symbols1
            slots = symbolSlots1
        }
        rebuildKeyLayers()
        layoutSpecialKeys(viewSize: bounds.size)
        updateSymbolToggleLabel()
        updateShiftForSymbolMode()
    }

    private func updateSymbolToggleLabel() {
        let theme = KeyboardTheme.current
        switch inputMode {
        case .letters:
            symbolToggleButton.setTitle("123", for: .normal)
            symbolToggleButton.backgroundColor = theme.buttonFillColor

            // Restore shift icon
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            shiftButton.setTitle(nil, for: .normal)
            shiftButton.setImage(UIImage(systemName: "shift")?.withConfiguration(config), for: .normal)
            shiftButton.backgroundColor = theme.buttonFillColor

        case .symbols1:
            symbolToggleButton.setTitle("ABC", for: .normal)
            symbolToggleButton.backgroundColor = theme.glowColor.withAlphaComponent(0.3)

            shiftButton.setImage(nil, for: .normal)
            shiftButton.setTitle("#+=", for: .normal)
            shiftButton.backgroundColor = theme.buttonFillColor

        case .symbols2:
            symbolToggleButton.setTitle("ABC", for: .normal)
            symbolToggleButton.backgroundColor = theme.glowColor.withAlphaComponent(0.3)

            shiftButton.setImage(nil, for: .normal)
            shiftButton.setTitle("123", for: .normal)
            shiftButton.backgroundColor = theme.buttonFillColor
        }
    }

    private func updateShiftForSymbolMode() {
        // In symbol mode, shift button becomes symbol set toggle — handled by updateSymbolToggleLabel
    }

    // MARK: - Touch handling (letters area only — buttons handle themselves)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if touch.view is UIButton { return }
        touchRouter.touchBegan(touch.location(in: self), timestamp: touch.timestamp)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchRouter.touchMoved(touch.location(in: self), timestamp: touch.timestamp)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchRouter.touchEnded(touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchRouter.touchCancelled()
    }
}
