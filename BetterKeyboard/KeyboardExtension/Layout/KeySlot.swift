import CoreGraphics

enum Ring: String {
    case inner
    case outer
    case grid
}

struct KeySlot {
    let letter: Character
    let ring: Ring
    let index: Int
    /// Angle in degrees (0 = right, CCW positive, math convention)
    let angleDeg: CGFloat
    /// Normalized position from optimizer (unit-circle scale)
    let normalizedPosition: CGPoint
    /// Angular width of this key's wedge in degrees
    var angularWidthDeg: CGFloat = 0
    /// Screen position (computed at layout time)
    var screenPosition: CGPoint = .zero

    // Grid-specific fields (ignored by ring layout and swipe pipeline)
    var gridRow: Int?
    var gridCol: Int?
    var keyWidth: CGFloat?
    var keyHeight: CGFloat?

    var letterString: String { String(letter) }
}

/// A key with a confidence weight from velocity-based swipe analysis.
/// High weight (near 1.0) = user decelerated here (intentional target).
/// Low weight (near 0.0) = finger passed through at speed (incidental).
struct WeightedKey {
    let slot: KeySlot
    let weight: CGFloat     // 0.0 (incidental) to 1.0 (deliberate target)
    let sampleIndex: Int    // index into raw path (for dedup/debugging)
}
