import UIKit

/// Classifies touches and routes them to the appropriate handler.
class TouchRouter {

    enum TouchMode {
        case none
        case centerHold       // center zone: dead space / long-hold cursor
        case centerCursor     // center zone after 2s hold: drag = cursor movement
        case keyTap(KeySlot)
        case ringSwipe
        case backspace
        case spaceZone        // right gap: tap = space, flick right = jump to end
    }

    private weak var ringView: RingView?
    private var mode: TouchMode = .none
    private var startPoint: CGPoint = .zero
    private var swipeTracker: SwipeTracker?

    // Center hold / cursor
    private var centerHoldTimer: Timer?
    private var cursorTimer: Timer?
    private var cursorOrigin: CGPoint = .zero
    private var cursorTouchPoint: CGPoint = .zero
    private var lastCursorPoint: CGPoint = .zero
    private var cursorAccumulator: CGFloat = 0
    private var cursorTimerAccumulator: CGFloat = 0

    /// Movement threshold to transition from tap to swipe
    private let swipeThreshold: CGFloat = 15.0
    /// How long to hold center before entering cursor mode
    private let centerHoldDuration: TimeInterval = 1.5
    /// Pixels of finger movement per cursor character step (trackpad style)
    private let cursorStepSize: CGFloat = 12.0
    /// Dead zone before continuous scrolling kicks in
    private let cursorDeadZone: CGFloat = 20.0
    /// Max cursor chars per second for continuous hold
    private let cursorMaxSpeed: CGFloat = 12.0
    /// Distance from origin for max speed
    private let cursorRampDistance: CGFloat = 80.0

    init(ringView: RingView) {
        self.ringView = ringView
    }

    // MARK: - Touch events

    func touchBegan(_ point: CGPoint) {
        guard let ringView = ringView else { return }
        startPoint = point

        let slots = ringView.slots
        let center = CGPoint(
            x: ringView.bounds.width / 2.0,
            y: ringView.bounds.height / 2.0
        )

        let distFromCenter = GeometryHelpers.distanceFromCenter(point, center: center)

        // Check center zone — dead space, long hold = cursor mode
        if distFromCenter < RingView.centerTapRadius {
            mode = .centerHold
            // Pre-arm swipe tracker so center-drag-to-swipe works
            swipeTracker = SwipeTracker(slots: slots)
            swipeTracker?.ringCenter = center
            swipeTracker?.begin(at: point, initialSlot: nil)
            // Start hold timer for cursor mode
            centerHoldTimer?.invalidate()
            centerHoldTimer = Timer.scheduledTimer(withTimeInterval: centerHoldDuration, repeats: false) { [weak self] _ in
                self?.activateCursorMode()
            }
            // Show glow building up
            ringView.showCenterHoldGlow()
            return
        }

        // Check gap zones — only in the outer ring radial range
        let angle = GeometryHelpers.angleDeg(from: center, to: point)
        let computedScale = ringView.bounds.height > 0
            ? (min(ringView.bounds.width, ringView.bounds.height) / 2.0 - 20.0)
              / (RingLayoutConfig.outerWedgeRMax + 0.1)
            : 1.0
        let outerRingMinR = RingLayoutConfig.outerWedgeRMin * computedScale

        // Only trigger gap zones when touch is in outer ring area
        if distFromCenter >= outerRingMinR {
            // Backspace zone (left gap around 180°)
            if GeometryHelpers.angleInGap(angle,
                                           gapCenter: RingLayoutConfig.leftGapAngle,
                                           gapWidth: RingLayoutConfig.gapWidthDeg) {
                mode = .backspace
                return
            }

            // Space zone (right gap around 0°) — tap=space
            if GeometryHelpers.angleInGap(angle,
                                           gapCenter: RingLayoutConfig.rightGapAngle,
                                           gapWidth: RingLayoutConfig.gapWidthDeg) {
                mode = .spaceZone
                return
            }
        }

        // Check nearest key (frequency-weighted, generous tap threshold)
        if let (nearest, dist) = GeometryHelpers.weightedNearestSlot(
            to: point, in: slots, maxDist: RingView.tapProximityThreshold),
           dist < RingView.tapProximityThreshold {
            mode = .keyTap(nearest)
            ringView.highlightKey(at: nearest.index)

            // Start swipe tracker in case this becomes a swipe
            swipeTracker = SwipeTracker(slots: slots)
            swipeTracker?.ringCenter = center
            swipeTracker?.begin(at: point, initialSlot: nearest)
            ringView.swipeTrail.beginTrail(at: point)
            return
        }

        // Anywhere else — start as potential swipe
        swipeTracker = SwipeTracker(slots: slots)
        swipeTracker?.ringCenter = center
        swipeTracker?.begin(at: point, initialSlot: nil)
        ringView.swipeTrail.beginTrail(at: point)
        mode = .ringSwipe
    }

    func touchMoved(_ point: CGPoint) {
        guard let ringView = ringView else { return }

        switch mode {
        case .centerHold:
            let moved = GeometryHelpers.distance(startPoint, point)
            if moved > swipeThreshold {
                // Cancel hold timer, transition to swipe
                centerHoldTimer?.invalidate()
                centerHoldTimer = nil
                ringView.hideCenterGlow()
                mode = .ringSwipe
                ringView.swipeTrail.beginTrail(at: startPoint)
                if let tracker = swipeTracker {
                    tracker.addSample(point)
                    ringView.swipeTrail.addPoint(point)
                }
            }

        case .centerCursor:
            // Displacement-based: immediate response to finger movement
            let dx = point.x - lastCursorPoint.x
            cursorAccumulator += dx
            lastCursorPoint = point
            cursorTouchPoint = point

            while cursorAccumulator > cursorStepSize {
                cursorAccumulator -= cursorStepSize
                ringView.delegate?.ringView(ringView, didMoveCursorRight: ())
            }
            while cursorAccumulator < -cursorStepSize {
                cursorAccumulator += cursorStepSize
                ringView.delegate?.ringView(ringView, didMoveCursorLeft: ())
            }

        case .keyTap:
            let moved = GeometryHelpers.distance(startPoint, point)
            if moved > swipeThreshold {
                mode = .ringSwipe
                ringView.unhighlightAllKeys()
            }
            if let tracker = swipeTracker {
                tracker.addSample(point)
                ringView.swipeTrail.addPoint(point)
                ringView.unhighlightAllKeys()
                if let current = tracker.currentSlot {
                    ringView.highlightKey(at: current.index)
                }
            }

        case .ringSwipe:
            if let tracker = swipeTracker {
                tracker.addSample(point)
                ringView.swipeTrail.addPoint(point)
                ringView.unhighlightAllKeys()
                if let current = tracker.currentSlot {
                    ringView.highlightKey(at: current.index)
                }
            }

        default:
            break
        }
    }

    func touchEnded(_ point: CGPoint) {
        guard let ringView = ringView else { return }

        defer {
            cleanup()
        }

        switch mode {
        case .centerHold:
            // Dead space — no action on short tap/release
            break

        case .centerCursor:
            break // Just stop cursor movement

        case .keyTap(let slot):
            let moved = GeometryHelpers.distance(startPoint, point)
            if moved <= swipeThreshold {
                ringView.delegate?.ringView(ringView, didTapLetter: slot.letter)
            } else {
                finalizeSwipe()
            }

        case .ringSwipe:
            if let tracker = swipeTracker {
                let visitedSlots = tracker.finalize()
                if !visitedSlots.isEmpty {
                    ringView.delegate?.ringView(ringView, didSwipeWord: visitedSlots)
                } else {
                    // No keys visited — check for center-to-gap directional swipe
                    let center = CGPoint(x: ringView.bounds.width / 2.0,
                                         y: ringView.bounds.height / 2.0)
                    let startedFromCenter = GeometryHelpers.distanceFromCenter(
                        startPoint, center: center) < RingView.centerTapRadius
                    let moved = GeometryHelpers.distance(startPoint, point)
                    if startedFromCenter && moved > swipeThreshold {
                        if point.x < startPoint.x {
                            ringView.delegate?.ringView(ringView, didDeleteWord: ())
                        } else if point.x > startPoint.x {
                            ringView.delegate?.ringView(ringView, didJumpToEnd: ())
                        }
                    }
                }
            }

        case .backspace:
            let moved = GeometryHelpers.distance(startPoint, point)
            let swipedLeft = point.x < startPoint.x
            if moved > swipeThreshold && swipedLeft {
                ringView.delegate?.ringView(ringView, didDeleteWord: ())
            } else if moved <= swipeThreshold {
                ringView.delegate?.ringView(ringView, didTapBackspace: ())
            }

        case .spaceZone:
            let moved = GeometryHelpers.distance(startPoint, point)
            let swipedRight = point.x > startPoint.x
            if moved > swipeThreshold && swipedRight {
                ringView.delegate?.ringView(ringView, didJumpToEnd: ())
            } else if moved <= swipeThreshold {
                ringView.delegate?.ringView(ringView, didTapSpace: ())
            }

        case .none:
            break
        }
    }

    func touchCancelled() {
        cleanup()
    }

    // MARK: - Cursor mode

    private func activateCursorMode() {
        guard let ringView = ringView else { return }
        mode = .centerCursor
        cursorOrigin = startPoint
        cursorTouchPoint = startPoint
        lastCursorPoint = startPoint
        cursorAccumulator = 0
        cursorTimerAccumulator = 0
        swipeTracker = nil
        ringView.showCenterCursorActive()

        // Timer for continuous scrolling when finger is held away from origin
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.fireCursorTick()
        }
    }

    /// Continuous scrolling: moves cursor when finger is held away from origin.
    private func fireCursorTick() {
        guard let ringView = ringView else { return }
        let dx = cursorTouchPoint.x - cursorOrigin.x
        let distance = abs(dx)
        guard distance > cursorDeadZone else {
            cursorTimerAccumulator = 0
            return
        }

        let t = min((distance - cursorDeadZone) / cursorRampDistance, 1.0)
        let speed = t * cursorMaxSpeed
        cursorTimerAccumulator += speed * 0.05
        let steps = Int(cursorTimerAccumulator)
        if steps > 0 {
            cursorTimerAccumulator -= CGFloat(steps)
            if dx > 0 {
                for _ in 0..<steps {
                    ringView.delegate?.ringView(ringView, didMoveCursorRight: ())
                }
            } else {
                for _ in 0..<steps {
                    ringView.delegate?.ringView(ringView, didMoveCursorLeft: ())
                }
            }
        }
    }

    // MARK: - Private

    private func finalizeSwipe() {
        guard let ringView = ringView,
              let tracker = swipeTracker else { return }
        let visitedSlots = tracker.finalize()
        if !visitedSlots.isEmpty {
            ringView.delegate?.ringView(ringView, didSwipeWord: visitedSlots)
        }
    }

    private func cleanup() {
        centerHoldTimer?.invalidate()
        centerHoldTimer = nil
        cursorTimer?.invalidate()
        cursorTimer = nil
        ringView?.hideCenterGlow()
        ringView?.unhighlightAllKeys()
        ringView?.swipeTrail.clearTrail()
        swipeTracker = nil
        mode = .none
    }
}
