import CoreGraphics

/// Tracks a swipe gesture across the ring, recording which keys are visited.
class SwipeTracker {

    private let slots: [KeySlot]
    private(set) var visitedSlots: [KeySlot] = []
    private(set) var currentSlot: KeySlot?

    private let proximityThreshold: CGFloat = RingView.swipeProximityThreshold

    /// Center of the ring in screen coordinates (set by caller)
    var ringCenter: CGPoint = .zero

    /// Track recent points for radial velocity detection
    private var recentPoints: [CGPoint] = []
    private let radialSampleCount = 3

    /// Minimum outward radial speed (pts per sample) to trigger suppression
    private let radialOutwardThreshold: CGFloat = 4.0

    /// Track movement direction angles for loop/circle detection (task #13)
    private var lastDirection: CGFloat?  // last absolute movement direction in degrees
    private var turnAccumulator: [CGFloat] = []  // recent signed turn deltas
    private let loopAngleThreshold: CGFloat = 300.0  // degrees of cumulative turn = circle
    private let loopWindowSize = 20

    init(slots: [KeySlot]) {
        self.slots = slots
    }

    func begin(at point: CGPoint, initialSlot: KeySlot?) {
        visitedSlots = []
        recentPoints = [point]
        lastDirection = nil
        turnAccumulator = []
        if let slot = initialSlot {
            visitedSlots.append(slot)
            currentSlot = slot
        } else {
            checkProximity(at: point)
        }
    }

    func addSample(_ point: CGPoint) {
        recentPoints.append(point)
        if recentPoints.count > radialSampleCount {
            recentPoints.removeFirst()
        }

        // Track angle changes for loop detection
        trackAngleChange(at: point)

        checkProximity(at: point)
    }

    func finalize() -> [KeySlot] {
        return visitedSlots
    }

    // MARK: - Radial velocity

    /// Returns positive if moving outward, negative if inward.
    private func radialVelocity() -> CGFloat {
        guard recentPoints.count >= 2 else { return 0 }
        let prev = recentPoints[recentPoints.count - 2]
        let curr = recentPoints[recentPoints.count - 1]
        let rPrev = GeometryHelpers.distanceFromCenter(prev, center: ringCenter)
        let rCurr = GeometryHelpers.distanceFromCenter(curr, center: ringCenter)
        return rCurr - rPrev
    }

    // MARK: - Loop detection for double letters

    private func trackAngleChange(at point: CGPoint) {
        guard recentPoints.count >= 2 else { return }
        let prev = recentPoints[recentPoints.count - 2]
        let curr = point

        let dx = curr.x - prev.x
        let dy = curr.y - prev.y
        guard dx * dx + dy * dy > 1.0 else { return }  // skip tiny movements

        let direction = atan2(dy, dx) * 180.0 / .pi

        if let last = lastDirection {
            var delta = direction - last
            // Normalize to -180..180
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            turnAccumulator.append(delta)

            // Keep window bounded
            if turnAccumulator.count > loopWindowSize {
                turnAccumulator.removeFirst()
            }
        }

        lastDirection = direction
    }

    /// Check if finger drew a loop recently (sum of angle deltas > threshold).
    private func detectLoop() -> Bool {
        guard turnAccumulator.count >= loopWindowSize / 2 else { return false }
        let totalTurn = turnAccumulator.suffix(loopWindowSize).reduce(0, +)
        if abs(totalTurn) >= loopAngleThreshold {
            turnAccumulator.removeAll()
            lastDirection = nil
            return true
        }
        return false
    }

    // MARK: - Proximity check

    private func checkProximity(at point: CGPoint) {
        guard let (nearest, dist) = GeometryHelpers.weightedNearestSlot(
            to: point, in: slots, maxDist: proximityThreshold),
              dist < proximityThreshold else {
            return
        }

        // Suppress inner ring keys when moving radially outward
        if nearest.ring == .inner && radialVelocity() > radialOutwardThreshold {
            return
        }

        // Check for loop → double letter
        if let last = visitedSlots.last, last.index == nearest.index {
            // Same key as last visited — check if we drew a loop (double letter)
            if detectLoop() {
                visitedSlots.append(nearest)
                currentSlot = nearest
            }
            return
        }

        // Don't add if it's the same as current (prevents duplicates from jitter)
        if let current = currentSlot, current.index == nearest.index {
            return
        }

        visitedSlots.append(nearest)
        currentSlot = nearest
    }
}
