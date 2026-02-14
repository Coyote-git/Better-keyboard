import UIKit
import QuartzCore

/// A single key on the ring: bracket-shaped outline + radially-oriented letter.
class KeyCapLayer: CAShapeLayer {

    let slot: KeySlot
    private let textLayer = CATextLayer()

    init(slot: KeySlot) {
        self.slot = slot
        super.init()
        setupLayers()
    }

    required init?(coder: NSCoder) { fatalError() }

    override init(layer: Any) {
        if let other = layer as? KeyCapLayer {
            self.slot = other.slot
        } else {
            self.slot = KeySlot(letter: "?", ring: .inner, index: 0,
                                angleDeg: 0, normalizedPosition: .zero,
                                angularWidthDeg: 0)
        }
        super.init(layer: layer)
    }

    private func setupLayers() {
        let theme = KeyboardTheme.current

        fillColor = nil
        strokeColor = theme.keyStrokeColor.cgColor
        lineWidth = theme.keyStrokeWidth
        lineCap = .round

        shadowColor = theme.glowColor.cgColor
        shadowRadius = 0
        shadowOpacity = 0
        shadowOffset = .zero

        textLayer.string = slot.letterString

        let fontSize: CGFloat
        let fontWeight: UIFont.Weight
        let textColor: UIColor
        switch slot.ring {
        case .inner:
            fontSize = theme.innerRingFontSize
            fontWeight = theme.innerRingFontWeight
            textColor = theme.innerRingTextColor
        case .outer:
            fontSize = theme.outerRingFontSize
            fontWeight = theme.outerRingFontWeight
            textColor = theme.outerRingTextColor
        }

        if theme.useMonospaceFont {
            textLayer.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: fontWeight)
        } else {
            textLayer.font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)
        }
        textLayer.fontSize = fontSize
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = textColor.cgColor
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.isWrapped = false
        addSublayer(textLayer)
    }

    /// Draw the key as two bracket marks at the angular edges of the key's wedge.
    func updateWedge(center: CGPoint, scale: CGFloat) {
        let theme = KeyboardTheme.current
        let halfAngle = (slot.angularWidthDeg / 2.0) - theme.keyGapInsetDeg
        guard halfAngle > 0 else { return }

        let startDeg = slot.angleDeg - halfAngle
        let endDeg = slot.angleDeg + halfAngle

        let rMin: CGFloat
        let rMax: CGFloat
        switch slot.ring {
        case .inner:
            rMin = RingLayoutConfig.innerWedgeRMin * scale
            rMax = RingLayoutConfig.innerWedgeRMax * scale
        case .outer:
            rMin = RingLayoutConfig.outerWedgeRMin * scale
            rMax = RingLayoutConfig.outerWedgeRMax * scale
        }

        if theme.showKeyBrackets {
            let armDeg = halfAngle * 0.55
            let bracketPath = UIBezierPath()

            drawBracket(into: bracketPath, center: center,
                        edgeDeg: startDeg, armDeg: armDeg,
                        rMin: rMin, rMax: rMax, openToward: 1.0)

            drawBracket(into: bracketPath, center: center,
                        edgeDeg: endDeg, armDeg: armDeg,
                        rMin: rMin, rMax: rMax, openToward: -1.0)

            path = bracketPath.cgPath
        } else {
            path = nil
        }

        let midR = (rMin + rMax) / 2.0
        let angleRad = -slot.angleDeg * .pi / 180.0
        let pos = CGPoint(x: center.x + midR * cos(angleRad),
                          y: center.y + midR * sin(angleRad))
        let textW: CGFloat = 36
        let textH: CGFloat = 20
        textLayer.bounds = CGRect(origin: .zero, size: CGSize(width: textW, height: textH))
        textLayer.position = pos

        let isTopHalf = slot.angleDeg > 0 && slot.angleDeg < 180
        let rotationDeg = isTopHalf ? (90.0 - slot.angleDeg) : (270.0 - slot.angleDeg)
        textLayer.transform = CATransform3DMakeRotation(rotationDeg * .pi / 180.0, 0, 0, 1)
    }

    private func drawBracket(into path: UIBezierPath, center: CGPoint,
                             edgeDeg: CGFloat, armDeg: CGFloat,
                             rMin: CGFloat, rMax: CGFloat,
                             openToward: CGFloat) {
        let edgeRad = -edgeDeg * .pi / 180.0
        let armEndDeg = edgeDeg + armDeg * openToward
        let armEndRad = -armEndDeg * .pi / 180.0

        path.move(to: CGPoint(x: center.x + rMax * cos(armEndRad),
                               y: center.y + rMax * sin(armEndRad)))

        path.addArc(withCenter: center, radius: rMax,
                    startAngle: armEndRad, endAngle: edgeRad,
                    clockwise: openToward > 0)

        path.addLine(to: CGPoint(x: center.x + rMin * cos(edgeRad),
                                  y: center.y + rMin * sin(edgeRad)))

        path.addArc(withCenter: center, radius: rMin,
                    startAngle: edgeRad, endAngle: armEndRad,
                    clockwise: openToward < 0)
    }

    func setHighlighted(_ highlighted: Bool) {
        let theme = KeyboardTheme.current
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if highlighted {
            strokeColor = theme.glowColor.cgColor
            textLayer.foregroundColor = theme.highlightTextColor.cgColor
            shadowRadius = 10
            shadowOpacity = 0.9
        } else {
            strokeColor = theme.keyStrokeColor.cgColor
            let textColor: UIColor = slot.ring == .inner
                ? theme.innerRingTextColor : theme.outerRingTextColor
            textLayer.foregroundColor = textColor.cgColor
            shadowRadius = 0
            shadowOpacity = 0
        }
        CATransaction.commit()

        if highlighted {
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [1.0, 1.25, 1.0]
            pulse.keyTimes = [0, 0.15, 1.0]
            pulse.duration = 0.2
            pulse.isRemovedOnCompletion = true
            textLayer.add(pulse, forKey: "pulse")
        }
    }
}
