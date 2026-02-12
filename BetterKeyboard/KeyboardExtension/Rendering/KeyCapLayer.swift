import UIKit
import QuartzCore

/// A single key on the ring: bracket-shaped outline + radially-oriented letter.
class KeyCapLayer: CAShapeLayer {

    let slot: KeySlot
    private let textLayer = CATextLayer()

    // LED glow theme
    static let glowColor = SwipeTrailLayer.glowColor
    static let bracketColor = UIColor(white: 0.35, alpha: 1.0).cgColor
    static let textColor = UIColor.white.cgColor
    static let highlightTextColor = SwipeTrailLayer.glowColor.cgColor

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
        fillColor = nil  // transparent — bracket outline only
        strokeColor = Self.bracketColor
        lineWidth = 1.0
        lineCap = .round

        // No glow by default
        shadowColor = Self.glowColor.cgColor
        shadowRadius = 0
        shadowOpacity = 0
        shadowOffset = .zero

        textLayer.string = slot.letterString
        switch slot.ring {
        case .inner: textLayer.fontSize = 16
        case .outer: textLayer.fontSize = 13
        }
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = Self.textColor
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.isWrapped = false
        addSublayer(textLayer)
    }

    /// Draw the key as two bracket marks at the angular edges of the key's wedge.
    func updateWedge(center: CGPoint, scale: CGFloat) {
        let halfAngle = (slot.angularWidthDeg / 2.0) - 1.0  // 1° inset gap
        guard halfAngle > 0 else { return }

        let startDeg = slot.angleDeg - halfAngle
        let endDeg = slot.angleDeg + halfAngle

        // Bracket radii: inner and outer keys meet at the midpoint (no gap)
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

        // Bracket arm: 30% of the usable half-angle on each side
        let armDeg = halfAngle * 0.55

        let bracketPath = UIBezierPath()

        // Left bracket (at startDeg side)
        drawBracket(into: bracketPath, center: center,
                    edgeDeg: startDeg, armDeg: armDeg,
                    rMin: rMin, rMax: rMax, openToward: 1.0)

        // Right bracket (at endDeg side)
        drawBracket(into: bracketPath, center: center,
                    edgeDeg: endDeg, armDeg: armDeg,
                    rMin: rMin, rMax: rMax, openToward: -1.0)

        path = bracketPath.cgPath

        // Position text at radial center of bracket (not ring radius)
        let midR = (rMin + rMax) / 2.0
        let angleRad = -slot.angleDeg * .pi / 180.0
        let pos = CGPoint(x: center.x + midR * cos(angleRad),
                          y: center.y + midR * sin(angleRad))
        let textW: CGFloat = 36
        let textH: CGFloat = 20
        textLayer.bounds = CGRect(origin: .zero, size: CGSize(width: textW, height: textH))
        textLayer.position = pos

        // Radial rotation: always upright, flipped at equator.
        // Top half (0°–180°): bottom of letter faces center → top faces up/outward
        // Bottom half (180°–360°): top of letter faces center → top faces up
        let isTopHalf = slot.angleDeg > 0 && slot.angleDeg < 180
        let rotationDeg = isTopHalf ? (90.0 - slot.angleDeg) : (270.0 - slot.angleDeg)
        textLayer.transform = CATransform3DMakeRotation(rotationDeg * .pi / 180.0, 0, 0, 1)
    }

    /// Draw one bracket arm (like `[` or `]`) as a single connected stroke:
    /// outer arc tip → radial edge → inner arc tip.
    private func drawBracket(into path: UIBezierPath, center: CGPoint,
                             edgeDeg: CGFloat, armDeg: CGFloat,
                             rMin: CGFloat, rMax: CGFloat,
                             openToward: CGFloat) {
        let edgeRad = -edgeDeg * .pi / 180.0
        let armEndDeg = edgeDeg + armDeg * openToward
        let armEndRad = -armEndDeg * .pi / 180.0

        // Start at outer arc tip (the far end of the arm)
        path.move(to: CGPoint(x: center.x + rMax * cos(armEndRad),
                               y: center.y + rMax * sin(armEndRad)))

        // Arc along outer radius back to the edge (short arc)
        path.addArc(withCenter: center, radius: rMax,
                    startAngle: armEndRad, endAngle: edgeRad,
                    clockwise: openToward > 0)

        // Radial line down to inner radius
        path.addLine(to: CGPoint(x: center.x + rMin * cos(edgeRad),
                                  y: center.y + rMin * sin(edgeRad)))

        // Arc along inner radius to inner arc tip (short arc)
        path.addArc(withCenter: center, radius: rMin,
                    startAngle: edgeRad, endAngle: armEndRad,
                    clockwise: openToward < 0)
    }

    func setHighlighted(_ highlighted: Bool) {
        if highlighted {
            strokeColor = Self.glowColor.cgColor
            textLayer.foregroundColor = Self.highlightTextColor
            shadowRadius = 10
            shadowOpacity = 0.9

            // Pulse animation
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [1.0, 1.25, 1.0]
            pulse.keyTimes = [0, 0.3, 1.0]
            pulse.duration = 0.3
            pulse.isRemovedOnCompletion = true
            textLayer.add(pulse, forKey: "pulse")
        } else {
            strokeColor = Self.bracketColor
            textLayer.foregroundColor = Self.textColor
            shadowRadius = 0
            shadowOpacity = 0
        }
    }

    func refreshColors() {
        // For dark/light mode changes — in LED mode, mostly static
        if shadowOpacity == 0 {
            strokeColor = Self.bracketColor
            textLayer.foregroundColor = Self.textColor
        }
    }
}
