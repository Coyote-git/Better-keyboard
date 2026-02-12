import CoreGraphics

enum GeometryHelpers {

    /// Euclidean distance between two points.
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Distance from a point to the center (origin).
    static func distanceFromCenter(_ point: CGPoint, center: CGPoint) -> CGFloat {
        distance(point, center)
    }

    /// Find the nearest KeySlot to a given screen point. Returns (slot, distance).
    static func nearestSlot(to point: CGPoint, in slots: [KeySlot]) -> (KeySlot, CGFloat)? {
        guard !slots.isEmpty else { return nil }
        var bestSlot = slots[0]
        var bestDist = distance(point, slots[0].screenPosition)
        for slot in slots.dropFirst() {
            let d = distance(point, slot.screenPosition)
            if d < bestDist {
                bestDist = d
                bestSlot = slot
            }
        }
        return (bestSlot, bestDist)
    }

    /// Frequency-weighted nearest slot: scores by (1/dist²) * letterFrequency.
    /// Returns the best slot and the raw distance to it (for threshold checks).
    static func weightedNearestSlot(to point: CGPoint, in slots: [KeySlot],
                                     maxDist: CGFloat) -> (KeySlot, CGFloat)? {
        guard !slots.isEmpty else { return nil }
        var bestSlot: KeySlot?
        var bestScore: CGFloat = -1
        var bestRawDist: CGFloat = .greatestFiniteMagnitude

        for slot in slots {
            let d = distance(point, slot.screenPosition)
            guard d < maxDist else { continue }

            let freq = letterFrequency[slot.letter] ?? 0.001
            // Avoid division by zero; clamp minimum distance
            let clampedDist = max(d, 1.0)
            let score = freq / (clampedDist * clampedDist)

            if score > bestScore {
                bestScore = score
                bestSlot = slot
                bestRawDist = d
            }
        }

        if let slot = bestSlot {
            return (slot, bestRawDist)
        }
        return nil
    }

    /// Angle in degrees from center to point (0 = right, CCW positive).
    static func angleDeg(from center: CGPoint, to point: CGPoint) -> CGFloat {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radians = atan2(dy, dx)
        let degrees = radians * 180.0 / .pi
        return degrees < 0 ? degrees + 360.0 : degrees
    }

    /// Check if an angle (degrees) falls within a gap.
    static func angleInGap(_ angleDeg: CGFloat,
                           gapCenter: CGFloat,
                           gapWidth: CGFloat) -> Bool {
        let half = gapWidth / 2.0
        let start = fmod(gapCenter - half + 360.0, 360.0)
        let end = fmod(gapCenter + half, 360.0)
        if start < end {
            return angleDeg >= start && angleDeg < end
        } else {
            return angleDeg >= start || angleDeg < end
        }
    }

    // MARK: - English letter frequencies (relative, sums to ~1.0)

    static let letterFrequency: [Character: CGFloat] = [
        "E": 0.127, "T": 0.091, "A": 0.082, "O": 0.075, "I": 0.070,
        "N": 0.067, "S": 0.063, "H": 0.061, "R": 0.060, "D": 0.043,
        "L": 0.040, "C": 0.028, "U": 0.028, "M": 0.024, "W": 0.024,
        "F": 0.022, "G": 0.020, "Y": 0.020, "P": 0.019, "B": 0.015,
        "V": 0.010, "K": 0.008, "J": 0.002, "X": 0.002, "Q": 0.001,
        "Z": 0.001,
    ]
}
