import UIKit
import QuartzCore

/// Renders the visible swipe path as the user drags their finger.
/// Old segments fade away after ~1 second, creating a comet-tail effect.
class SwipeTrailLayer: CAShapeLayer {

    private var timedPoints: [(point: CGPoint, time: TimeInterval)] = []

    override init() {
        super.init()
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    func applyTheme() {
        let theme = KeyboardTheme.current
        fillColor = nil
        strokeColor = theme.trailColor.withAlphaComponent(0.8).cgColor
        lineWidth = theme.trailLineWidth
        lineCap = .round
        lineJoin = .round

        shadowColor = theme.trailColor.cgColor
        shadowRadius = theme.trailGlowRadius
        shadowOpacity = theme.trailGlowOpacity
        shadowOffset = .zero
    }

    func beginTrail(at point: CGPoint) {
        timedPoints = [(point, CACurrentMediaTime())]
        updatePath()
    }

    func addPoint(_ point: CGPoint) {
        let now = CACurrentMediaTime()
        timedPoints.append((point, now))

        // Trim points older than 1 second
        let cutoff = now - 1.0
        if let firstValid = timedPoints.firstIndex(where: { $0.time >= cutoff }) {
            if firstValid > 0 {
                timedPoints.removeFirst(firstValid)
            }
        }

        updatePath()
    }

    func clearTrail() {
        timedPoints = []
        path = nil
    }

    private func updatePath() {
        guard timedPoints.count >= 2 else {
            path = nil
            return
        }
        let bezier = UIBezierPath()
        bezier.move(to: timedPoints[0].point)
        for tp in timedPoints.dropFirst() {
            bezier.addLine(to: tp.point)
        }
        path = bezier.cgPath
    }
}
