import UIKit
import QuartzCore

/// Renders the visible swipe path as the user drags their finger.
class SwipeTrailLayer: CAShapeLayer {

    static let glowColor = UIColor(red: 1.0, green: 0.1, blue: 0.55, alpha: 1.0) // hot pink

    private var points: [CGPoint] = []

    override init() {
        super.init()
        fillColor = nil
        strokeColor = Self.glowColor.withAlphaComponent(0.8).cgColor
        lineWidth = 2.5
        lineCap = .round
        lineJoin = .round

        // LED glow
        shadowColor = Self.glowColor.cgColor
        shadowRadius = 8
        shadowOpacity = 0.9
        shadowOffset = .zero
    }

    required init?(coder: NSCoder) { fatalError() }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    func beginTrail(at point: CGPoint) {
        points = [point]
        updatePath()
    }

    func addPoint(_ point: CGPoint) {
        points.append(point)
        if points.count > 200 {
            points = stride(from: 0, to: points.count, by: 2).map { points[$0] }
        }
        updatePath()
    }

    func clearTrail() {
        points = []
        path = nil
    }

    private func updatePath() {
        guard points.count >= 2 else {
            path = nil
            return
        }
        let bezier = UIBezierPath()
        bezier.move(to: points[0])
        for p in points.dropFirst() {
            bezier.addLine(to: p)
        }
        path = bezier.cgPath
    }
}
