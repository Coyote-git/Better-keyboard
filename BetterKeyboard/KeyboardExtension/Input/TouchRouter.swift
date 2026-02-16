import UIKit

/// Classifies touches and routes them to the appropriate handler.
/// Modes: tap a key, swipe across keys, hold center (cursor), tap gap zones.
class TouchRouter {

    enum Mode {
        case none
        case centerHold       // center zone: waiting for 1s hold timer
        case centerSwipe      // swiped from center horizontally, resolves on lift
        case centerCursor     // cursor mode active: distance-from-center = speed
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

    // MARK: - Cursor mode state

    private var holdTimer: Timer?
    private var cursorTimer: Timer?
    private var cursorTouchPoint: CGPoint = .zero
    private var cursorAccumulator: CGFloat = 0.0

    /// Minimum distance from center (in pts) before cursor starts moving.
    private let cursorDeadZone: CGFloat = 10.0
    /// Characters per second at maximum distance.
    private let cursorMaxSpeed: CGFloat = 20.0
    /// Distance (in pts) at which max speed is reached.
    private let cursorMaxDistance: CGFloat = 120.0
    /// Cursor timer fires at 60 Hz for smooth movement.
    private let cursorTickInterval: TimeInterval = 1.0 / 60.0

    init(ringView: RingView) {
        self.ringView = ringView
    }

    // MARK: - Touch events

    func touchBegan(_ point: CGPoint, timestamp: TimeInterval) {
        guard let ringView = ringView else { return }
        startPoint = point

        let slots = ringView.slots
        let center = CGPoint(x: ringView.bounds.midX, y: ringView.bounds.midY)
        let distFromCenter = GeometryHelpers.distanceFromCenter(point, center: center)

        // 1. Center zone → hold for cursor mode, drag to swipe
        if distFromCenter < RingView.centerTapRadius {
            mode = .centerHold
            cursorTouchPoint = point
            swipeTracker = SwipeTracker(slots: slots)
            swipeTracker?.ringCenter = center
            swipeTracker?.begin(at: point, timestamp: timestamp, initialSlot: nil)
            ringView.showCenterHoldGlow()
            startHoldTimer()
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
            swipeTracker?.begin(at: point, timestamp: timestamp, initialSlot: nearest)
            ringView.swipeTrail.beginTrail(at: point)
            return
        }

        // 4. Anywhere else → start as swipe
        swipeTracker = SwipeTracker(slots: slots)
        swipeTracker?.ringCenter = center
        swipeTracker?.begin(at: point, timestamp: timestamp, initialSlot: nil)
        ringView.swipeTrail.beginTrail(at: point)
        mode = .ringSwipe
    }

    func touchMoved(_ point: CGPoint, timestamp: TimeInterval) {
        guard let ringView = ringView else { return }

        switch mode {
        case .centerHold:
            if GeometryHelpers.distance(startPoint, point) > swipeThreshold {
                cancelHoldTimer()
                ringView.hideCursorMode()

                let dx = point.x - startPoint.x
                let dy = point.y - startPoint.y

                if abs(dx) > abs(dy) * 1.5 {
                    // Predominantly horizontal → center swipe gesture
                    mode = .centerSwipe
                } else {
                    // Diagonal/vertical → ring swipe for word input
                    mode = .ringSwipe
                    ringView.swipeTrail.beginTrail(at: startPoint)
                    swipeTracker?.addSample(point, timestamp: timestamp)
                    ringView.swipeTrail.addPoint(point)
                }
            }

        case .centerSwipe:
            break

        case .centerCursor:
            cursorTouchPoint = point

        case .keyTap:
            if GeometryHelpers.distance(startPoint, point) > swipeThreshold {
                mode = .ringSwipe
                ringView.unhighlightAllKeys()
            }
            swipeTracker?.addSample(point, timestamp: timestamp)
            ringView.swipeTrail.addPoint(point)
            ringView.unhighlightAllKeys()
            if let current = swipeTracker?.currentSlot {
                ringView.highlightKey(at: current.index)
            }

        case .ringSwipe:
            swipeTracker?.addSample(point, timestamp: timestamp)
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
        case .centerHold:
            // Hold didn't complete and finger didn't move — do nothing
            break

        case .centerSwipe:
            let dx = point.x - startPoint.x
            if dx < 0 {
                ringView.delegate?.ringView(ringView, didDeleteWord: ())
            } else {
                ringView.delegate?.ringView(ringView, didJumpToEnd: ())
            }

        case .centerCursor:
            ringView.hideCursorMode()

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
        ringView?.hideCursorMode()
        cleanup()
    }

    // MARK: - Hold timer

    private func startHoldTimer() {
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.activateCursorMode()
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func activateCursorMode() {
        holdTimer = nil
        mode = .centerCursor
        cursorAccumulator = 0.0
        ringView?.showCursorActivation()
        startCursorTimer()
    }

    // MARK: - Cursor timer

    private func startCursorTimer() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: cursorTickInterval,
                                           repeats: true) { [weak self] _ in
            self?.cursorTick()
        }
    }

    private func cursorTick() {
        guard let ringView = ringView else { return }
        let center = CGPoint(x: ringView.bounds.midX, y: ringView.bounds.midY)

        let dx = cursorTouchPoint.x - center.x
        let dist = abs(dx)

        guard dist > cursorDeadZone else { return }

        let effective = min(dist - cursorDeadZone, cursorMaxDistance - cursorDeadZone)
        let speed = cursorMaxSpeed * effective / (cursorMaxDistance - cursorDeadZone)
        let direction: CGFloat = dx > 0 ? 1.0 : -1.0

        cursorAccumulator += direction * speed * CGFloat(cursorTickInterval)

        let steps = Int(cursorAccumulator)
        if steps != 0 {
            cursorAccumulator -= CGFloat(steps)
            ringView.delegate?.ringView(ringView, didMoveCursor: steps)
        }
    }

    // MARK: - Private

    private func finalizeSwipe() {
        guard let ringView = ringView,
              let tracker = swipeTracker else { return }
        let keys = tracker.finalize()
        if !keys.isEmpty {
            ringView.delegate?.ringView(ringView, didSwipeWord: keys)
        }
    }

    private func cleanup() {
        cancelHoldTimer()
        cursorTimer?.invalidate()
        cursorTimer = nil
        ringView?.unhighlightAllKeys()
        ringView?.swipeTrail.endTrail()
        swipeTracker = nil
        mode = .none
    }
}
