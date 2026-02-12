import UIKit

/// Classifies touches and routes them to the appropriate handler.
/// Modes: tap a key, swipe across keys, tap center (space), tap gap zones.
class TouchRouter {

    enum Mode {
        case none
        case centerTap        // center zone: tap = space, drag = swipe
        case keyTap(KeySlot)  // near a key: tap = letter, drag = swipe
        case ringSwipe        // finger is swiping across the ring
        case backspace        // backspace gap zone
        case spaceZone        // space gap zone
    }

    private weak var ringView: RingView?
    private var mode: Mode = .none
    private var startPoint: CGPoint = .zero
    private var swipeTracker: SwipeTracker?

    private let swipeThreshold: CGFloat = 15.0

    init(ringView: RingView) {
        self.ringView = ringView
    }

    // MARK: - Touch events

    func touchBegan(_ point: CGPoint) {
        guard let ringView = ringView else { return }
        startPoint = point

        let slots = ringView.slots
        let center = CGPoint(x: ringView.bounds.midX, y: ringView.bounds.midY)
        let distFromCenter = GeometryHelpers.distanceFromCenter(point, center: center)

        // 1. Center zone → tap = space, drag = transition to swipe
        if distFromCenter < RingView.centerTapRadius {
            mode = .centerTap
            swipeTracker = SwipeTracker(slots: slots)
            swipeTracker?.ringCenter = center
            swipeTracker?.begin(at: point, initialSlot: nil)
            return
        }

        // 2. Gap zones (only in outer ring radial range)
        let angle = GeometryHelpers.angleDeg(from: center, to: point)
        let scale = ringView.currentScale
        let outerRingMinR = RingLayoutConfig.outerWedgeRMin * scale

        if distFromCenter >= outerRingMinR {
            if GeometryHelpers.angleInGap(angle,
                                           gapCenter: RingLayoutConfig.leftGapAngle,
                                           gapWidth: RingLayoutConfig.gapWidthDeg) {
                mode = .backspace
                return
            }
            if GeometryHelpers.angleInGap(angle,
                                           gapCenter: RingLayoutConfig.rightGapAngle,
                                           gapWidth: RingLayoutConfig.gapWidthDeg) {
                mode = .spaceZone
                return
            }
        }

        // 3. Near a key → tap or swipe
        if let (nearest, dist) = GeometryHelpers.weightedNearestSlot(
            to: point, in: slots, maxDist: RingView.tapProximityThreshold),
           dist < RingView.tapProximityThreshold {
            mode = .keyTap(nearest)
            ringView.highlightKey(at: nearest.index)
            swipeTracker = SwipeTracker(slots: slots)
            swipeTracker?.ringCenter = center
            swipeTracker?.begin(at: point, initialSlot: nearest)
            ringView.swipeTrail.beginTrail(at: point)
            return
        }

        // 4. Anywhere else → start as swipe
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
            if GeometryHelpers.distance(startPoint, point) > swipeThreshold {
                mode = .ringSwipe
                ringView.swipeTrail.beginTrail(at: startPoint)
                swipeTracker?.addSample(point)
                ringView.swipeTrail.addPoint(point)
            }

        case .keyTap:
            if GeometryHelpers.distance(startPoint, point) > swipeThreshold {
                mode = .ringSwipe
                ringView.unhighlightAllKeys()
            }
            swipeTracker?.addSample(point)
            ringView.swipeTrail.addPoint(point)
            ringView.unhighlightAllKeys()
            if let current = swipeTracker?.currentSlot {
                ringView.highlightKey(at: current.index)
            }

        case .ringSwipe:
            swipeTracker?.addSample(point)
            ringView.swipeTrail.addPoint(point)
            ringView.unhighlightAllKeys()
            if let current = swipeTracker?.currentSlot {
                ringView.highlightKey(at: current.index)
            }

        default:
            break
        }
    }

    func touchEnded(_ point: CGPoint) {
        guard let ringView = ringView else { return }
        defer { cleanup() }

        switch mode {
        case .centerTap:
            ringView.delegate?.ringView(ringView, didTapSpace: ())

        case .keyTap(let slot):
            if GeometryHelpers.distance(startPoint, point) <= swipeThreshold {
                ringView.delegate?.ringView(ringView, didTapLetter: slot.letter)
            } else {
                finalizeSwipe()
            }

        case .ringSwipe:
            finalizeSwipe()

        case .backspace:
            let moved = GeometryHelpers.distance(startPoint, point)
            if moved > swipeThreshold && point.x < startPoint.x {
                ringView.delegate?.ringView(ringView, didDeleteWord: ())
            } else if moved <= swipeThreshold {
                ringView.delegate?.ringView(ringView, didTapBackspace: ())
            }

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
        let visited = tracker.finalize()
        if !visited.isEmpty {
            ringView.delegate?.ringView(ringView, didSwipeWord: visited)
        }
    }

    private func cleanup() {
        ringView?.unhighlightAllKeys()
        ringView?.swipeTrail.clearTrail()
        swipeTracker = nil
        mode = .none
    }
}
