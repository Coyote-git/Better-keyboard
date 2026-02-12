import CoreGraphics

enum Ring: String {
    case inner
    case outer
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

    var letterString: String { String(letter) }
}
