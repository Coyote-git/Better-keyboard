import UIKit

protocol RingViewDelegate: AnyObject {
    func ringView(_ ringView: RingView, didTapLetter letter: Character)
    func ringView(_ ringView: RingView, didTapSpace: Void)
    func ringView(_ ringView: RingView, didTapBackspace: Void)
    func ringView(_ ringView: RingView, didSwipeWord keys: [WeightedKey])
    func ringView(_ ringView: RingView, didTapShift: Void)
    func ringView(_ ringView: RingView, didTapReturn: Void)
    func ringView(_ ringView: RingView, didDeleteWord: Void)
    func ringView(_ ringView: RingView, didTapPunctuation character: Character)
    func ringView(_ ringView: RingView, didMoveCursor offset: Int)
    func ringView(_ ringView: RingView, didJumpToEnd: Void)
    func ringView(_ ringView: RingView, didTapDismiss: Void)
    func ringView(_ ringView: RingView, didChangeTheme: Void)
}

class RingView: UIView {

    weak var delegate: RingViewDelegate?

    // MARK: - Layout state

    enum InputMode {
        case letters
        case symbols1
        case symbols2
    }

    private(set) var slots: [KeySlot] = []
    private var letterSlots: [KeySlot] = []
    private var symbolSlots: [KeySlot] = []
    private var symbolSlots2: [KeySlot] = []
    private(set) var inputMode: InputMode = .letters
    private var center_: CGPoint = .zero
    private(set) var currentScale: CGFloat = 1.0

    // MARK: - Layers

    private let backspaceZone = CAShapeLayer()
    private let spaceZone = CAShapeLayer()
    private let centerZone = CAShapeLayer()
    private let backspaceIcon = CAShapeLayer()
    private let spaceIcon = CAShapeLayer()
    private var keyCapLayers: [KeyCapLayer] = []
    let swipeTrail = SwipeTrailLayer()

    // MARK: - Buttons

    private var punctuationButtons: [UIButton] = []
    private var functionButtons: [UIButton] = []
    private let themeButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)

    // MARK: - Input

    private lazy var touchRouter = TouchRouter(ringView: self)

    // MARK: - Constants

    static let centerTapRadius: CGFloat = 30.0
    static let tapProximityThreshold: CGFloat = 44.0
    static let swipeProximityThreshold: CGFloat = 26.0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KeyboardTheme.current.backgroundColor
        setupLayers()
        setupButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Configuration

    func configure(viewSize: CGSize) {
        let layout = RingLayoutConfig.computeLayout(viewSize: viewSize)
        center_ = layout.center
        currentScale = layout.scale

        letterSlots = RingLayoutConfig.makeSlots()
        RingLayoutConfig.applyScreenPositions(slots: &letterSlots, center: center_, scale: currentScale)

        symbolSlots = RingLayoutConfig.makeSymbolSlots()
        RingLayoutConfig.applyScreenPositions(slots: &symbolSlots, center: center_, scale: currentScale)

        symbolSlots2 = RingLayoutConfig.makeSymbolSlots2()
        RingLayoutConfig.applyScreenPositions(slots: &symbolSlots2, center: center_, scale: currentScale)

        switch inputMode {
        case .letters:  slots = letterSlots
        case .symbols1: slots = symbolSlots
        case .symbols2: slots = symbolSlots2
        }
        rebuildLayers()
    }

    // MARK: - Theme

    func reapplyTheme() {
        let theme = KeyboardTheme.current
        backgroundColor = theme.backgroundColor
        swipeTrail.applyTheme()

        rebuildLayers()

        for btn in punctuationButtons + functionButtons {
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

        themeButton.tintColor = theme.buttonTextColor
        dismissButton.tintColor = theme.buttonTextColor

        // Restore correct button labels/highlights after theme reset
        updateFunctionButtons()
    }

    // MARK: - Shift

    func updateShiftAppearance(isShifted: Bool, isCapsLocked: Bool) {
        let theme = KeyboardTheme.current
        guard !functionButtons.isEmpty else { return }
        let btn = functionButtons[0]
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setTitle(nil, for: .normal)

        if isCapsLocked {
            btn.setImage(UIImage(systemName: "capslock.fill")?.withConfiguration(config), for: .normal)
            btn.tintColor = theme.buttonTextColor
            btn.backgroundColor = theme.glowColor.withAlphaComponent(0.6)
        } else {
            btn.setImage(UIImage(systemName: "shift")?.withConfiguration(config), for: .normal)
            btn.tintColor = theme.buttonTextColor
            btn.backgroundColor = isShifted
                ? theme.glowColor.withAlphaComponent(0.3) : theme.buttonFillColor
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

    // MARK: - Layer setup

    private func setupLayers() {
        for l in [backspaceZone, spaceZone, centerZone] {
            layer.addSublayer(l)
        }
        layer.addSublayer(backspaceIcon)
        layer.addSublayer(spaceIcon)
        layer.addSublayer(swipeTrail)
    }

    private func rebuildLayers() {
        keyCapLayers.forEach { $0.removeFromSuperlayer() }
        keyCapLayers.removeAll()

        drawGapZones()
        drawCenterZone()

        for slot in slots {
            let keyCap = KeyCapLayer(slot: slot)
            keyCap.updateWedge(center: center_, scale: currentScale)
            layer.addSublayer(keyCap)
            keyCapLayers.append(keyCap)
        }

        swipeTrail.removeFromSuperlayer()
        layer.addSublayer(swipeTrail)

        layoutButtons()
    }

    // MARK: - Gap zone drawing

    private func drawGapZones() {
        let theme = KeyboardTheme.current

        drawGapWedge(layer: backspaceZone,
                     gapCenter: RingLayoutConfig.leftGapAngle,
                     fillColor: theme.backspaceFillColor.cgColor)
        drawBackspaceSlashes(color: theme.backspaceIconColor)

        drawGapWedge(layer: spaceZone,
                     gapCenter: RingLayoutConfig.rightGapAngle,
                     fillColor: theme.spaceFillColor.cgColor)
        drawCursorChevrons(color: theme.spaceIconColor)
    }

    private func drawGapWedge(layer wedgeLayer: CAShapeLayer,
                              gapCenter: CGFloat, fillColor: CGColor) {
        let theme = KeyboardTheme.current
        let halfGap = RingLayoutConfig.gapWidthDeg / 2.0
        let startRad = -(gapCenter - halfGap) * .pi / 180.0
        let endRad = -(gapCenter + halfGap) * .pi / 180.0

        let rInner = RingLayoutConfig.outerWedgeRMin * currentScale
        let rOuter = RingLayoutConfig.outerWedgeRMax * currentScale

        let path = UIBezierPath()
        path.addArc(withCenter: center_, radius: rOuter,
                    startAngle: startRad, endAngle: endRad, clockwise: false)
        path.addArc(withCenter: center_, radius: rInner,
                    startAngle: endRad, endAngle: startRad, clockwise: true)
        path.close()

        wedgeLayer.path = path.cgPath
        wedgeLayer.fillColor = fillColor
        wedgeLayer.strokeColor = theme.gapStrokeColor.cgColor
        wedgeLayer.lineWidth = 0.5
    }

    /// Draw 45-degree slashes in the backspace gap zone.
    private func drawBackspaceSlashes(color: UIColor) {
        let midR = (RingLayoutConfig.outerWedgeRMin + RingLayoutConfig.outerWedgeRMax) / 2.0 * currentScale
        let angleRad = -RingLayoutConfig.leftGapAngle * .pi / 180.0
        let cx = center_.x + midR * cos(angleRad)
        let cy = center_.y + midR * sin(angleRad)

        let slashLen: CGFloat = 10
        let spacing: CGFloat = 6
        let path = UIBezierPath()

        for i in -1...1 {
            let ox = cx + CGFloat(i) * spacing
            path.move(to: CGPoint(x: ox - slashLen / 2, y: cy + slashLen / 2))
            path.addLine(to: CGPoint(x: ox + slashLen / 2, y: cy - slashLen / 2))
        }

        backspaceIcon.path = path.cgPath
        backspaceIcon.strokeColor = color.cgColor
        backspaceIcon.lineWidth = 2.0
        backspaceIcon.fillColor = nil
        backspaceIcon.lineCap = .round
    }

    /// Draw right-pointing chevrons in the cursor-advance gap zone.
    private func drawCursorChevrons(color: UIColor) {
        let midR = (RingLayoutConfig.outerWedgeRMin + RingLayoutConfig.outerWedgeRMax) / 2.0 * currentScale
        let angleRad = -RingLayoutConfig.rightGapAngle * .pi / 180.0
        let cx = center_.x + midR * cos(angleRad)
        let cy = center_.y + midR * sin(angleRad)

        let chevH: CGFloat = 10
        let chevW: CGFloat = 6
        let spacing: CGFloat = 7
        let path = UIBezierPath()

        for i in -1...1 {
            let ox = cx + CGFloat(i) * spacing
            path.move(to: CGPoint(x: ox - chevW / 2, y: cy - chevH / 2))
            path.addLine(to: CGPoint(x: ox + chevW / 2, y: cy))
            path.addLine(to: CGPoint(x: ox - chevW / 2, y: cy + chevH / 2))
        }

        spaceIcon.path = path.cgPath
        spaceIcon.strokeColor = color.cgColor
        spaceIcon.lineWidth = 2.0
        spaceIcon.fillColor = nil
        spaceIcon.lineCap = .round
        spaceIcon.lineJoin = .round
    }

    // MARK: - Center zone

    private func drawCenterZone() {
        let theme = KeyboardTheme.current
        let r = Self.centerTapRadius
        let path = UIBezierPath(ovalIn: CGRect(x: center_.x - r, y: center_.y - r,
                                               width: r * 2, height: r * 2))
        centerZone.path = path.cgPath
        centerZone.fillColor = theme.centerFillColor.cgColor
        centerZone.strokeColor = theme.centerStrokeColor.cgColor
        centerZone.lineWidth = 0.5
    }

    // MARK: - Cursor mode visuals

    /// Subtle glow building up during the 1s hold period.
    func showCenterHoldGlow() {
        let anim = CABasicAnimation(keyPath: "fillColor")
        anim.toValue = KeyboardTheme.current.glowColor.withAlphaComponent(0.15).cgColor
        anim.duration = 1.0
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        centerZone.add(anim, forKey: "holdGlow")
    }

    /// Large pulse ring + haptic when cursor mode activates.
    func showCursorActivation() {
        let theme = KeyboardTheme.current
        centerZone.removeAnimation(forKey: "holdGlow")

        centerZone.fillColor = theme.glowColor.withAlphaComponent(0.2).cgColor
        centerZone.shadowColor = theme.glowColor.cgColor
        centerZone.shadowRadius = 12
        centerZone.shadowOpacity = 0.6
        centerZone.shadowOffset = .zero

        let pulse = CAShapeLayer()
        let r = Self.centerTapRadius
        pulse.path = UIBezierPath(ovalIn: CGRect(x: center_.x - r, y: center_.y - r,
                                                  width: r * 2, height: r * 2)).cgPath
        pulse.fillColor = nil
        pulse.strokeColor = theme.glowColor.cgColor
        pulse.lineWidth = 2.0
        pulse.opacity = 0
        layer.addSublayer(pulse)

        let expand = CABasicAnimation(keyPath: "transform.scale")
        expand.fromValue = 1.0
        expand.toValue = 4.0
        expand.duration = 0.5

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.8
        fade.toValue = 0.0
        fade.duration = 0.5

        let group = CAAnimationGroup()
        group.animations = [expand, fade]
        group.duration = 0.5
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        pulse.add(group, forKey: "pulse")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            pulse.removeFromSuperlayer()
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Reset center zone to default appearance.
    func hideCursorMode() {
        centerZone.removeAnimation(forKey: "holdGlow")
        centerZone.fillColor = KeyboardTheme.current.centerFillColor.cgColor
        centerZone.shadowOpacity = 0
        centerZone.shadowRadius = 0
    }

    // MARK: - Buttons

    private func setupButtons() {
        let theme = KeyboardTheme.current

        let punctTitles = [".", ",", "'", "\"", "?", "!"]
        for (i, title) in punctTitles.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            btn.setTitleColor(theme.buttonTextColor, for: .normal)
            btn.backgroundColor = theme.buttonFillColor
            btn.layer.cornerRadius = theme.buttonCornerRadius
            if let borderColor = theme.buttonBorderColor {
                btn.layer.borderColor = borderColor.cgColor
                btn.layer.borderWidth = theme.buttonBorderWidth
            }
            btn.tag = i
            btn.addTarget(self, action: #selector(punctuationTapped(_:)), for: .touchUpInside)
            addSubview(btn)
            punctuationButtons.append(btn)
        }

        let funcTitles: [String?] = [nil, "123", "\u{21B5}"]
        let funcImages: [String?] = ["shift", nil, nil]
        for (i, title) in funcTitles.enumerated() {
            let btn = UIButton(type: .system)
            if let title = title {
                btn.setTitle(title, for: .normal)
            }
            if let imageName = funcImages[i] {
                let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                btn.setImage(UIImage(systemName: imageName)?.withConfiguration(config), for: .normal)
                btn.tintColor = theme.buttonTextColor
            }
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            btn.setTitleColor(theme.buttonTextColor, for: .normal)
            btn.backgroundColor = theme.buttonFillColor
            btn.layer.cornerRadius = theme.buttonCornerRadius
            if let borderColor = theme.buttonBorderColor {
                btn.layer.borderColor = borderColor.cgColor
                btn.layer.borderWidth = theme.buttonBorderWidth
            }
            btn.tag = i
            btn.addTarget(self, action: #selector(functionTapped(_:)), for: .touchUpInside)
            addSubview(btn)
            functionButtons.append(btn)
        }

        // Theme toggle
        themeButton.setImage(UIImage(systemName: "circle.lefthalf.filled"), for: .normal)
        themeButton.tintColor = theme.buttonTextColor
        themeButton.addTarget(self, action: #selector(themeTapped), for: .touchUpInside)
        addSubview(themeButton)

        // Dismiss keyboard
        let dismissConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        dismissButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down")?.withConfiguration(dismissConfig), for: .normal)
        dismissButton.tintColor = theme.buttonTextColor
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        addSubview(dismissButton)

    }

    private func layoutButtons() {
        let radius = RingLayoutConfig.buttonArcRadius * currentScale
        let funcBtnSize: CGFloat = 34.0
        let punctBtnSize: CGFloat = 30.0

        // Punctuation: place at equal vertical spacing along the left arc.
        // Fixed angular spacing looks uneven because buttons are axis-aligned
        // (gaps shrink at arc edges where separation becomes diagonal).
        // Equal vertical spacing gives consistent visual gaps.
        let punctGap: CGFloat = 3.0
        let verticalStep = punctBtnSize + punctGap
        let halfCount = CGFloat(punctuationButtons.count - 1) / 2.0
        for (i, btn) in punctuationButtons.enumerated() {
            let yOffset = (CGFloat(i) - halfCount) * verticalStep
            let x = center_.x - sqrt(max(0, radius * radius - yOffset * yOffset))
            let y = center_.y + yOffset
            btn.frame = CGRect(x: x - punctBtnSize / 2, y: y - punctBtnSize / 2,
                               width: punctBtnSize, height: punctBtnSize)
        }

        let funcAngles: [CGFloat] = [15, 0, 345]
        for (i, btn) in functionButtons.enumerated() {
            let rad = -funcAngles[i] * .pi / 180.0
            btn.frame = CGRect(x: center_.x + radius * cos(rad) - funcBtnSize / 2,
                               y: center_.y + radius * sin(rad) - funcBtnSize / 2,
                               width: funcBtnSize, height: funcBtnSize)
        }

        themeButton.frame = CGRect(x: 8, y: 4, width: 30, height: 30)
        dismissButton.frame = CGRect(x: bounds.width - 38, y: 4, width: 30, height: 30)
    }

    @objc private func punctuationTapped(_ sender: UIButton) {
        let chars: [Character] = [".", ",", "'", "\"", "?", "!"]
        guard sender.tag < chars.count else { return }
        delegate?.ringView(self, didTapPunctuation: chars[sender.tag])
    }

    @objc private func functionTapped(_ sender: UIButton) {
        switch sender.tag {
        case 0:
            // In letter mode: shift. In symbol mode: toggle between sets.
            if inputMode == .letters {
                delegate?.ringView(self, didTapShift: ())
            } else {
                toggleSymbolSet()
            }
        case 1:
            // Always toggles between letters ↔ symbols1
            toggleSymbolMode()
        case 2:
            delegate?.ringView(self, didTapReturn: ())
        default: break
        }
    }

    @objc private func themeTapped() {
        KeyboardTheme.cycle()
        reapplyTheme()
        delegate?.ringView(self, didChangeTheme: ())
    }

    @objc private func dismissTapped() {
        delegate?.ringView(self, didTapDismiss: ())
    }

    /// Toggle between letters and symbols1. From either symbol set, returns to letters.
    private func toggleSymbolMode() {
        if inputMode == .letters {
            inputMode = .symbols1
            slots = symbolSlots
        } else {
            inputMode = .letters
            slots = letterSlots
        }
        rebuildLayers()
        updateFunctionButtons()
    }

    /// Swap between symbol set 1 and 2 (called from button[0] in symbol mode).
    private func toggleSymbolSet() {
        if inputMode == .symbols1 {
            inputMode = .symbols2
            slots = symbolSlots2
        } else {
            inputMode = .symbols1
            slots = symbolSlots
        }
        rebuildLayers()
        updateFunctionButtons()
    }

    /// Update function button labels/icons based on current input mode.
    private func updateFunctionButtons() {
        let theme = KeyboardTheme.current
        guard functionButtons.count > 1 else { return }

        let btn0 = functionButtons[0]
        let btn1 = functionButtons[1]

        switch inputMode {
        case .letters:
            // button[0] = shift icon, button[1] = "123"
            let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            btn0.setTitle(nil, for: .normal)
            btn0.setImage(UIImage(systemName: "shift")?.withConfiguration(config), for: .normal)
            btn0.tintColor = theme.buttonTextColor
            btn0.backgroundColor = theme.buttonFillColor

            btn1.setImage(nil, for: .normal)
            btn1.setTitle("123", for: .normal)
            btn1.backgroundColor = theme.buttonFillColor

        case .symbols1:
            // button[0] = "#+=", button[1] = "ABC"
            btn0.setImage(nil, for: .normal)
            btn0.setTitle("#+=", for: .normal)
            btn0.backgroundColor = theme.buttonFillColor

            btn1.setImage(nil, for: .normal)
            btn1.setTitle("ABC", for: .normal)
            btn1.backgroundColor = theme.glowColor.withAlphaComponent(0.3)

        case .symbols2:
            // button[0] = "123", button[1] = "ABC"
            btn0.setImage(nil, for: .normal)
            btn0.setTitle("123", for: .normal)
            btn0.backgroundColor = theme.buttonFillColor

            btn1.setImage(nil, for: .normal)
            btn1.setTitle("ABC", for: .normal)
            btn1.backgroundColor = theme.glowColor.withAlphaComponent(0.3)
        }
    }

    // MARK: - Touch handling

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
