import UIKit
import QuartzCore

/// A single key on the grid keyboard: rounded rectangle + centered text label.
class GridKeyCapLayer: CAShapeLayer {

    let slot: KeySlot
    private let textLayer = CATextLayer()

    init(slot: KeySlot) {
        self.slot = slot
        super.init()
        setupLayers()
    }

    required init?(coder: NSCoder) { fatalError() }

    override init(layer: Any) {
        if let other = layer as? GridKeyCapLayer {
            self.slot = other.slot
        } else {
            self.slot = KeySlot(letter: "?", ring: .grid, index: 0,
                                angleDeg: 0, normalizedPosition: .zero)
        }
        super.init(layer: layer)
    }

    private func setupLayers() {
        let theme = KeyboardTheme.current

        // Rounded rect background
        fillColor = theme.buttonFillColor.cgColor
        strokeColor = nil
        cornerRadius = theme.buttonCornerRadius

        // Glow for highlight state
        shadowColor = theme.glowColor.cgColor
        shadowRadius = 0
        shadowOpacity = 0
        shadowOffset = .zero

        // Text
        textLayer.string = slot.letterString
        let fontSize: CGFloat = 18
        textLayer.font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        textLayer.fontSize = fontSize
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = theme.buttonTextColor.cgColor
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.isWrapped = false
        addSublayer(textLayer)
    }

    /// Position and size the key cap at its slot's screen location.
    func updateLayout() {
        let w = slot.keyWidth ?? GridLayoutConfig.baseKeyWidth
        let h = slot.keyHeight ?? GridLayoutConfig.baseKeyHeight
        let pos = slot.screenPosition

        // CAShapeLayer frame
        frame = CGRect(x: pos.x - w / 2, y: pos.y - h / 2, width: w, height: h)

        // Rounded rect path
        let rect = CGRect(origin: .zero, size: CGSize(width: w, height: h))
        path = UIBezierPath(roundedRect: rect,
                            cornerRadius: KeyboardTheme.current.buttonCornerRadius).cgPath

        // Center text vertically
        let textH: CGFloat = 22
        textLayer.bounds = CGRect(origin: .zero, size: CGSize(width: w, height: textH))
        textLayer.position = CGPoint(x: w / 2, y: h / 2)
    }

    func setHighlighted(_ highlighted: Bool) {
        let theme = KeyboardTheme.current
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if highlighted {
            fillColor = theme.glowColor.withAlphaComponent(0.4).cgColor
            textLayer.foregroundColor = theme.highlightTextColor.cgColor
            shadowRadius = 8
            shadowOpacity = 0.7
        } else {
            fillColor = theme.buttonFillColor.cgColor
            textLayer.foregroundColor = theme.buttonTextColor.cgColor
            shadowRadius = 0
            shadowOpacity = 0
        }
        CATransaction.commit()

        if highlighted {
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [1.0, 1.15, 1.0]
            pulse.keyTimes = [0, 0.15, 1.0]
            pulse.duration = 0.15
            pulse.isRemovedOnCompletion = true
            textLayer.add(pulse, forKey: "pulse")
        }
    }

    /// Update text label (used when toggling shift to show upper/lowercase).
    func updateLabel(_ text: String) {
        textLayer.string = text
    }
}
