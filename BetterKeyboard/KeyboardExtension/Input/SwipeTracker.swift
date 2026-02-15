import Foundation

/// Tracks a swipe gesture across the ring, recording the raw path.
/// On finger lift, analyzes velocity to extract intentional key targets
/// (velocity minima = deliberate letters) vs incidental pass-throughs.
class SwipeTracker {

    private let slots: [KeySlot]
    private(set) var currentSlot: KeySlot?

    private let proximityThreshold: CGFloat = RingView.swipeProximityThreshold

    /// Center of the ring in screen coordinates (set by caller)
    var ringCenter: CGPoint = .zero

    // MARK: - Raw path storage

    /// Every touch sample with its timestamp, recorded during the swipe.
    private var path: [(point: CGPoint, time: TimeInterval)] = []

    // MARK: - Tunable constants

    /// Velocity smoothing window in samples (~83ms at 60Hz)
    private let smoothingWindow = 5
    /// Velocity below this (pts/sec) counts as "dwelling near a key"
    private let dwellThreshold: CGFloat = 120.0
    /// Merge minima within this many samples to prevent jitter duplicates
    private let minimaMergeDistance = 3
    /// Weight assigned to pass-through keys between anchors
    private let passThruWeight: CGFloat = 0.15
    /// Search radius multiplier for finding keys at velocity minima
    private let anchorSearchRadiusMultiplier: CGFloat = 1.5

    // MARK: - Loop detection (for double letters)

    /// Windowed turn-angle accumulation detects circular gestures that
    /// velocity analysis misses (smoothing averages out brief direction changes).
    private var lastMoveDirection: CGFloat?
    private var turnDeltas: [CGFloat] = []
    private var loopDoubledKeys: [(slot: KeySlot, sampleIndex: Int)] = []
    private let loopWindowSize = 20        // ~333ms at 60Hz
    private let loopAngleThreshold: CGFloat = 300.0  // degrees of cumulative turn = circle

    init(slots: [KeySlot]) {
        self.slots = slots
    }

    func begin(at point: CGPoint, timestamp: TimeInterval, initialSlot: KeySlot?) {
        path = [(point, timestamp)]
        currentSlot = initialSlot
        lastMoveDirection = nil
        turnDeltas = []
        loopDoubledKeys = []
        if initialSlot == nil {
            updateCurrentSlot(at: point)
        }
    }

    func addSample(_ point: CGPoint, timestamp: TimeInterval) {
        path.append((point, timestamp))
        updateCurrentSlot(at: point)
        trackAngularChange(at: point, sampleIndex: path.count - 1)
    }

    /// Lightweight per-sample nearest-key check for real-time highlight feedback.
    private func updateCurrentSlot(at point: CGPoint) {
        if let (nearest, dist) = GeometryHelpers.weightedNearestSlot(
            to: point, in: slots, maxDist: proximityThreshold),
           dist < proximityThreshold {
            currentSlot = nearest
        }
    }

    // MARK: - Loop detection

    /// Track movement direction changes to detect circular/loop gestures.
    /// When windowed cumulative turning exceeds threshold, record the
    /// current key as a loop-doubled letter.
    private func trackAngularChange(at point: CGPoint, sampleIndex: Int) {
        guard path.count >= 2 else { return }
        let prev = path[path.count - 2].point
        let dx = point.x - prev.x
        let dy = point.y - prev.y
        guard dx * dx + dy * dy > 1.0 else { return }  // skip sub-pixel jitter

        let direction = atan2(dy, dx) * 180.0 / .pi

        if let last = lastMoveDirection {
            var delta = direction - last
            // Normalize to -180..180
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            turnDeltas.append(delta)
            if turnDeltas.count > loopWindowSize {
                turnDeltas.removeFirst()
            }

            // Fire when windowed turn exceeds threshold
            if turnDeltas.count >= loopWindowSize / 2 {
                let totalTurn = turnDeltas.suffix(loopWindowSize).reduce(0, +)
                if abs(totalTurn) >= loopAngleThreshold {
                    // Double whichever key the finger is currently near
                    if let slot = currentSlot {
                        loopDoubledKeys.append((slot, sampleIndex))
                    }
                    // Reset for next potential loop
                    turnDeltas.removeAll()
                    lastMoveDirection = nil
                    return
                }
            }
        }

        lastMoveDirection = direction
    }

    /// Inject loop-detected double letters into the weighted key sequence.
    /// Only adds a second instance if velocity analysis didn't already catch it.
    private func injectLoopDoubles(into keys: [WeightedKey]) -> [WeightedKey] {
        guard !loopDoubledKeys.isEmpty else { return keys }

        var result = keys
        for (loopSlot, loopSampleIdx) in loopDoubledKeys {
            let existingCount = result.filter { $0.slot.index == loopSlot.index }.count
            if existingCount < 2 {
                // Insert after the existing instance of this key
                if let insertAfter = result.lastIndex(where: { $0.slot.index == loopSlot.index }) {
                    let doubled = WeightedKey(slot: loopSlot, weight: 0.8, sampleIndex: loopSampleIdx)
                    result.insert(doubled, at: insertAfter + 1)
                }
            }
        }

        return result
    }

    // MARK: - Finalize: velocity-weighted key extraction

    /// Runs once on finger lift. Analyzes the recorded path using velocity
    /// to determine which keys the user intended vs. passed through.
    func finalize() -> [WeightedKey] {
        guard path.count >= 2 else {
            // Single point — shouldn't reach here (TouchRouter handles taps)
            // but handle gracefully: return the one key if near one
            if let slot = currentSlot {
                return [WeightedKey(slot: slot, weight: 1.0, sampleIndex: 0)]
            }
            return []
        }

        // Step 1: Compute per-sample velocity (pts/sec)
        let velocities = computeVelocities()

        // Step 2: Smooth velocity with moving average
        let smoothed = smoothVelocities(velocities)

        // Step 3: Find velocity minima (dwell points) + endpoints as anchors
        let minimaIndices = findVelocityMinima(smoothed)

        // Step 4: Convert minima to high-weight keys
        var result = extractAnchorKeys(at: minimaIndices, smoothedVelocities: smoothed)

        // Step 5: Add low-weight pass-through keys between anchors
        result = insertPassThroughKeys(anchors: result)

        // Step 6: Inject loop-detected double letters (catches what velocity misses)
        result = injectLoopDoubles(into: result)

        return result
    }

    // MARK: - Step 1: Per-sample velocity

    private func computeVelocities() -> [CGFloat] {
        var velocities = [CGFloat](repeating: 0, count: path.count)
        for i in 1..<path.count {
            let dx = path[i].point.x - path[i - 1].point.x
            let dy = path[i].point.y - path[i - 1].point.y
            let dist = sqrt(dx * dx + dy * dy)
            let dt = path[i].time - path[i - 1].time
            velocities[i] = dt > 0 ? dist / CGFloat(dt) : 0
        }
        // First sample gets same velocity as second (no predecessor)
        if path.count >= 2 { velocities[0] = velocities[1] }
        return velocities
    }

    // MARK: - Step 2: Smooth velocity

    private func smoothVelocities(_ raw: [CGFloat]) -> [CGFloat] {
        guard raw.count > 1 else { return raw }
        var smoothed = [CGFloat](repeating: 0, count: raw.count)
        let halfW = smoothingWindow / 2
        for i in 0..<raw.count {
            let lo = max(0, i - halfW)
            let hi = min(raw.count - 1, i + halfW)
            var sum: CGFloat = 0
            for j in lo...hi { sum += raw[j] }
            smoothed[i] = sum / CGFloat(hi - lo + 1)
        }
        return smoothed
    }

    // MARK: - Step 3: Find velocity minima

    private func findVelocityMinima(_ smoothed: [CGFloat]) -> [Int] {
        var minima: [Int] = []

        // Always include first sample as anchor
        minima.append(0)

        // Find local minima below dwell threshold
        for i in 1..<(smoothed.count - 1) {
            if smoothed[i] < dwellThreshold
                && smoothed[i] <= smoothed[i - 1]
                && smoothed[i] <= smoothed[i + 1] {
                // Merge with previous minimum if too close
                if let last = minima.last, (i - last) < minimaMergeDistance {
                    // Keep whichever has lower velocity
                    if smoothed[i] < smoothed[last] {
                        minima[minima.count - 1] = i
                    }
                } else {
                    minima.append(i)
                }
            }
        }

        // Always include last sample as anchor
        let lastIdx = smoothed.count - 1
        if let last = minima.last, last != lastIdx {
            if (lastIdx - last) < minimaMergeDistance {
                // Merge: replace with last index (endpoint takes priority)
                minima[minima.count - 1] = lastIdx
            } else {
                minima.append(lastIdx)
            }
        }

        return minima
    }

    // MARK: - Step 4: Convert minima to anchor keys

    private func extractAnchorKeys(at indices: [Int],
                                    smoothedVelocities: [CGFloat]) -> [WeightedKey] {
        let searchRadius = proximityThreshold * anchorSearchRadiusMultiplier
        var anchors: [WeightedKey] = []

        for idx in indices {
            let point = path[idx].point
            guard let (nearest, dist) = GeometryHelpers.weightedNearestSlot(
                to: point, in: slots, maxDist: searchRadius),
                  dist < searchRadius else { continue }

            // Endpoints always weight 1.0; interior minima weighted by velocity
            let isEndpoint = (idx == 0 || idx == path.count - 1)
            let weight: CGFloat
            if isEndpoint {
                weight = 1.0
            } else {
                weight = max(0.1, min(1.0, 1.0 - smoothedVelocities[idx] / 200.0))
            }

            // Double-letter detection: same key as previous anchor only if
            // velocity peaked between the two visits
            if let lastAnchor = anchors.last,
               lastAnchor.slot.index == nearest.index {
                // Check if velocity peaked between them
                let prevIdx = lastAnchor.sampleIndex
                var maxVel: CGFloat = 0
                for j in prevIdx...idx {
                    maxVel = max(maxVel, smoothedVelocities[j])
                }
                // Only add as double letter if there was a clear velocity peak between
                if maxVel > dwellThreshold * 1.5 {
                    anchors.append(WeightedKey(slot: nearest, weight: weight, sampleIndex: idx))
                }
                // Otherwise skip (same key, no separation)
            } else {
                anchors.append(WeightedKey(slot: nearest, weight: weight, sampleIndex: idx))
            }
        }

        return anchors
    }

    // MARK: - Step 5: Insert pass-through keys between anchors

    private func insertPassThroughKeys(anchors: [WeightedKey]) -> [WeightedKey] {
        guard anchors.count >= 2 else { return anchors }

        var result: [WeightedKey] = []

        for i in 0..<anchors.count {
            result.append(anchors[i])

            // Between this anchor and the next, scan path for nearby keys
            if i < anchors.count - 1 {
                let startIdx = anchors[i].sampleIndex + 1
                let endIdx = anchors[i + 1].sampleIndex
                var seenIndices: Set<Int> = []

                // Don't add pass-throughs that duplicate the surrounding anchors
                seenIndices.insert(anchors[i].slot.index)
                seenIndices.insert(anchors[i + 1].slot.index)

                for j in startIdx..<endIdx {
                    let point = path[j].point
                    if let (nearest, dist) = GeometryHelpers.weightedNearestSlot(
                        to: point, in: slots, maxDist: proximityThreshold),
                       dist < proximityThreshold,
                       !seenIndices.contains(nearest.index) {
                        seenIndices.insert(nearest.index)
                        result.append(WeightedKey(slot: nearest, weight: passThruWeight,
                                                  sampleIndex: j))
                    }
                }
            }
        }

        return result
    }
}
