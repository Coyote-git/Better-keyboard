import UIKit

protocol RingViewDelegate: AnyObject {
    func ringView(_ ringView: RingView, didTapLetter letter: Character)
    func ringView(_ ringView: RingView, didTapSpace: Void)
    func ringView(_ ringView: RingView, didTapBackspace: Void)
    func ringView(_ ringView: RingView, didSwipeWord slots: [KeySlot])
    func ringView(_ ringView: RingView, didTapShift: Void)
    func ringView(_ ringView: RingView, didTapReturn: Void)
    func ringView(_ ringView: RingView, didDeleteWord: Void)
    func ringView(_ ringView: RingView, didTapPunctuation character: Character)
    func ringView(_ ringView: RingView, didMoveCursor offset: Int)
    func ringView(_ ringView: RingView, didJumpToEnd: Void)
}

class RingView: UIView {

    weak var delegate: RingViewDelegate?

    // MARK: - Layout state

    private(set) var slots: [KeySlot] = []
    private var letterSlots: [KeySlot] = []
    private var symbolSlots: [KeySlot] = []
    private(set) var isSymbolMode = false
    private var center_: CGPoint = .zero
    private(set) var currentScale: CGFloat = 1.0

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

    // MARK: - Buttons

    private var punctuationButtons: [UIButton] = []
    private var functionButtons: [UIButton] = []

    // MARK: - Theme

    private static let bgColor = UIColor.black
    private static let dimColor = UIColor(white: 0.15, alpha: 1.0)
    private static let subtleStroke = UIColor(white: 0.25, alpha: 1.0)
    private static let labelColor = UIColor(white: 0.5, alpha: 1.0)
    private static let glowColor = SwipeTrailLayer.glowColor

    // MARK: - Input

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

        slots = isSymbolMode ? symbolSlots : letterSlots
        rebuildLayers()
    }

    // MARK: - Shift

    func updateShiftAppearance(isShifted: Bool) {
        guard !functionButtons.isEmpty else { return }
        functionButtons[0].backgroundColor = isShifted
            ? Self.glowColor.withAlphaComponent(0.3) : Self.dimColor
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
        for l in [innerRingArc, outerRingArc, backspaceZone, spaceZone, centerZone] {
            layer.addSublayer(l)
        }
        layer.addSublayer(backspaceLabel)
        layer.addSublayer(spaceLabel)
        layer.addSublayer(swipeTrail)
    }

    private func rebuildLayers() {
        keyCapLayers.forEach { $0.removeFromSuperlayer() }
        keyCapLayers.removeAll()

        drawRingArcs()
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

    // MARK: - Ring arc drawing

    private func drawRingArcs() {
        let seg1Start = -RingLayoutConfig.arcStartDeg * .pi / 180.0
        let seg1End = -RingLayoutConfig.arcEndDeg * .pi / 180.0
        let seg2Start = -(RingLayoutConfig.leftGapAngle + RingLayoutConfig.gapWidthDeg / 2.0) * .pi / 180.0
        let seg2End = -(360.0 - RingLayoutConfig.gapWidthDeg / 2.0) * .pi / 180.0

        for (ringLayer, radius) in [(innerRingArc, RingLayoutConfig.innerRadius),
                                     (outerRingArc, RingLayoutConfig.outerRadius)] {
            let r = radius * currentScale
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

    // MARK: - Gap zone drawing

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
        wedgeLayer.strokeColor = Self.subtleStroke.withAlphaComponent(0.3).cgColor
        wedgeLayer.lineWidth = 0.5
    }

    private func positionGapLabel(_ textLayer: CATextLayer, text: String,
                                  gapCenter: CGFloat, fontSize: CGFloat) {
        let midR = (RingLayoutConfig.outerWedgeRMin + RingLayoutConfig.outerWedgeRMax) / 2.0 * currentScale
        let angleRad = -gapCenter * .pi / 180.0
        let cx = center_.x + midR * cos(angleRad)
        let cy = center_.y + midR * sin(angleRad)

        let size = CGSize(width: 60, height: 24)
        textLayer.frame = CGRect(x: cx - size.width / 2, y: cy - size.height / 2,
                                 width: size.width, height: size.height)
        textLayer.string = text
        textLayer.fontSize = fontSize
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = Self.labelColor.cgColor
        textLayer.contentsScale = UIScreen.main.scale
    }

    // MARK: - Center zone

    private func drawCenterZone() {
        let r = Self.centerTapRadius
        let path = UIBezierPath(ovalIn: CGRect(x: center_.x - r, y: center_.y - r,
                                               width: r * 2, height: r * 2))
        centerZone.path = path.cgPath
        centerZone.fillColor = Self.dimColor.cgColor
        centerZone.strokeColor = Self.subtleStroke.cgColor
        centerZone.lineWidth = 0.5
    }

    // MARK: - Cursor mode visuals

    /// Subtle glow building up during the 1s hold period.
    func showCenterHoldGlow() {
        let anim = CABasicAnimation(keyPath: "fillColor")
        anim.toValue = Self.glowColor.withAlphaComponent(0.15).cgColor
        anim.duration = 1.0
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        centerZone.add(anim, forKey: "holdGlow")
    }

    /// Large pulse ring + haptic when cursor mode activates.
    func showCursorActivation() {
        centerZone.removeAnimation(forKey: "holdGlow")

        // Set center to active glow
        centerZone.fillColor = Self.glowColor.withAlphaComponent(0.2).cgColor
        centerZone.shadowColor = Self.glowColor.cgColor
        centerZone.shadowRadius = 12
        centerZone.shadowOpacity = 0.6
        centerZone.shadowOffset = .zero

        // Expanding pulse ring
        let pulse = CAShapeLayer()
        let r = Self.centerTapRadius
        pulse.path = UIBezierPath(ovalIn: CGRect(x: center_.x - r, y: center_.y - r,
                                                  width: r * 2, height: r * 2)).cgPath
        pulse.fillColor = nil
        pulse.strokeColor = Self.glowColor.cgColor
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
        centerZone.fillColor = Self.dimColor.cgColor
        centerZone.shadowOpacity = 0
        centerZone.shadowRadius = 0
    }

    // MARK: - Buttons

    private func setupButtons() {
        let punctTitles = [".", ",", "'", "?", "!"]
        for (i, title) in punctTitles.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = Self.dimColor
            btn.layer.cornerRadius = 8
            btn.tag = i
            btn.addTarget(self, action: #selector(punctuationTapped(_:)), for: .touchUpInside)
            addSubview(btn)
            punctuationButtons.append(btn)
        }

        let funcTitles = ["\u{21E7}", "123", "\u{21B5}"]
        for (i, title) in funcTitles.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = Self.dimColor
            btn.layer.cornerRadius = 8
            btn.tag = i
            btn.addTarget(self, action: #selector(functionTapped(_:)), for: .touchUpInside)
            addSubview(btn)
            functionButtons.append(btn)
        }
    }

    private func layoutButtons() {
        let radius = RingLayoutConfig.buttonArcRadius * currentScale
        let btnSize: CGFloat = 34.0

        let punctAngles: [CGFloat] = [150, 165, 180, 195, 210]
        for (i, btn) in punctuationButtons.enumerated() {
            let rad = -punctAngles[i] * .pi / 180.0
            btn.frame = CGRect(x: center_.x + radius * cos(rad) - btnSize / 2,
                               y: center_.y + radius * sin(rad) - btnSize / 2,
                               width: btnSize, height: btnSize)
        }

        let funcAngles: [CGFloat] = [15, 0, 345]
        for (i, btn) in functionButtons.enumerated() {
            let rad = -funcAngles[i] * .pi / 180.0
            btn.frame = CGRect(x: center_.x + radius * cos(rad) - btnSize / 2,
                               y: center_.y + radius * sin(rad) - btnSize / 2,
                               width: btnSize, height: btnSize)
        }
    }

    @objc private func punctuationTapped(_ sender: UIButton) {
        let chars: [Character] = [".", ",", "'", "?", "!"]
        guard sender.tag < chars.count else { return }
        delegate?.ringView(self, didTapPunctuation: chars[sender.tag])
    }

    @objc private func functionTapped(_ sender: UIButton) {
        switch sender.tag {
        case 0: delegate?.ringView(self, didTapShift: ())
        case 1: toggleSymbolMode()
        case 2: delegate?.ringView(self, didTapReturn: ())
        default: break
        }
    }

    private func toggleSymbolMode() {
        isSymbolMode.toggle()
        slots = isSymbolMode ? symbolSlots : letterSlots
        rebuildLayers()
        guard functionButtons.count > 1 else { return }
        functionButtons[1].backgroundColor = isSymbolMode
            ? Self.glowColor.withAlphaComponent(0.3) : Self.dimColor
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if touch.view is UIButton { return }
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
