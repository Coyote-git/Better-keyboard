import CoreGraphics

/// Hardcoded layout from optimizer output.
/// Positions are in normalized coordinates (inner ring radius = 1.0, outer = 2.2).
/// Screen positions are computed at layout time by applying center + scale.
enum RingLayoutConfig {

    // MARK: - Ring geometry

    static let innerRadius: CGFloat = 1.0
    static let outerRadius: CGFloat = 2.2

    /// Gap centers in degrees (math convention: 0=right, CCW positive)
    static let leftGapAngle: CGFloat = 180.0   // backspace
    static let rightGapAngle: CGFloat = 0.0     // reserved
    static let gapWidthDeg: CGFloat = 36.0
    static let usableArcDeg: CGFloat = 288.0
    static let arcStartDeg: CGFloat = 18.0      // right after right gap
    static let arcEndDeg: CGFloat = 162.0        // just before left gap

    // MARK: - Wedge geometry

    static let innerKeyAngularWidth: CGFloat = 288.0 / 8.0   // 36°
    static let outerKeyAngularWidth: CGFloat = 288.0 / 18.0   // 16°

    static let innerWedgeRMin: CGFloat = innerRadius * 0.6                    // 0.6
    static let innerWedgeRMax: CGFloat = (innerRadius + outerRadius) / 2.0    // 1.6
    static let outerWedgeRMin: CGFloat = (innerRadius + outerRadius) / 2.0    // 1.6
    static let outerWedgeRMax: CGFloat = outerRadius + 0.15                   // 2.35

    // Arc button radius (punctuation + function buttons along outer ring curve)
    static let buttonArcRadius: CGFloat = outerWedgeRMax + 0.80              // 3.15

    // MARK: - Key slots (from optimizer run)

    static func makeSlots() -> [KeySlot] {
        let data: [(Character, Ring, Int, CGFloat, CGFloat, CGFloat)] = [
            // Inner ring (8 slots) — all top-8 frequency letters
            ("H", .inner, 0,  36.0,  0.809,   0.5878),
            ("N", .inner, 1,  72.0,  0.309,   0.9511),
            ("S", .inner, 2, 108.0, -0.309,   0.9511),
            ("T", .inner, 3, 144.0, -0.809,   0.5878),
            ("E", .inner, 4, 216.0, -0.809,  -0.5878),
            ("A", .inner, 5, 252.0, -0.309,  -0.9511),
            ("I", .inner, 6, 288.0,  0.309,  -0.9511),
            ("O", .inner, 7, 324.0,  0.809,  -0.5878),
            // Outer ring (18 slots) — rare letters toward bottom-right
            ("B", .outer,  8,  26.0,  1.9773,  0.9644),
            ("V", .outer,  9,  42.0,  1.6349,  1.4721),
            ("M", .outer, 10,  58.0,  1.1658,  1.8657),
            ("R", .outer, 11,  74.0,  0.6064,  2.1148),
            ("L", .outer, 12,  90.0,  0.0,     2.2),
            ("W", .outer, 13, 106.0, -0.6064,  2.1148),
            ("C", .outer, 14, 122.0, -1.1658,  1.8657),
            ("D", .outer, 15, 138.0, -1.6349,  1.4721),
            ("F", .outer, 16, 154.0, -1.9773,  0.9644),
            // — left gap (162°–198°) —
            ("G", .outer, 17, 206.0, -1.9773, -0.9644),
            ("P", .outer, 18, 222.0, -1.6349, -1.4721),
            ("U", .outer, 19, 238.0, -1.1658, -1.8657),
            ("Y", .outer, 20, 254.0, -0.6064, -2.1148),
            ("K", .outer, 21, 270.0,  0.0,    -2.2),
            ("J", .outer, 22, 286.0,  0.6064, -2.1148),
            ("Q", .outer, 23, 302.0,  1.1658, -1.8657),
            ("Z", .outer, 24, 318.0,  1.6349, -1.4721),
            ("X", .outer, 25, 334.0,  1.9773, -0.9644),
        ]
        return data.map { letter, ring, idx, angle, x, y in
            var slot = KeySlot(letter: letter, ring: ring, index: idx,
                               angleDeg: angle,
                               normalizedPosition: CGPoint(x: x, y: y))
            slot.angularWidthDeg = (ring == .inner) ? innerKeyAngularWidth : outerKeyAngularWidth
            return slot
        }
    }

    // MARK: - Symbol/number slots (10 inner digits + 18 outer symbols)

    static func makeSymbolSlots() -> [KeySlot] {
        // Inner ring: 10 digits across full 360° (fills gap angles at 0° and 180°)
        let innerData: [(Character, CGFloat, CGFloat, CGFloat)] = [
            ("1",  36.0,  0.809,   0.5878),
            ("2",  72.0,  0.309,   0.9511),
            ("3", 108.0, -0.309,   0.9511),
            ("4", 144.0, -0.809,   0.5878),
            ("5", 180.0, -1.0,     0.0),
            ("6", 216.0, -0.809,  -0.5878),
            ("7", 252.0, -0.309,  -0.9511),
            ("8", 288.0,  0.309,  -0.9511),
            ("9", 324.0,  0.809,  -0.5878),
            ("0",   0.0,  1.0,     0.0),
        ]

        var slots: [KeySlot] = []
        for (i, (char, angle, x, y)) in innerData.enumerated() {
            var slot = KeySlot(letter: char, ring: .inner, index: i,
                               angleDeg: angle,
                               normalizedPosition: CGPoint(x: x, y: y))
            slot.angularWidthDeg = 36.0
            slots.append(slot)
        }

        // Outer ring: 18 symbols at same angular positions as letter layout
        // Upper (26°→154°, right-to-left visually): .  ,  !  ?  &  @  #  )  (
        // Lower (206°→334°, left-to-right visually): -  +  =  /  *  :  ;  "  '
        let outerSymbols: [Character] = [".", ",", "!", "?", "&", "@", "#", ")", "(",
                                          "-", "+", "=", "/", "*", ":", ";", "\"", "'"]
        let letterSlots = makeSlots().filter { $0.ring == .outer }
        for (i, ls) in letterSlots.enumerated() {
            let slot = KeySlot(letter: outerSymbols[i], ring: .outer,
                               index: innerData.count + i,
                               angleDeg: ls.angleDeg,
                               normalizedPosition: ls.normalizedPosition,
                               angularWidthDeg: ls.angularWidthDeg)
            slots.append(slot)
        }

        return slots
    }

    // MARK: - Symbol/number slots set 2 (10 inner digits + 18 outer brackets/currency/special)

    static func makeSymbolSlots2() -> [KeySlot] {
        // Inner ring: same 10 digits as set 1
        let innerData: [(Character, CGFloat, CGFloat, CGFloat)] = [
            ("1",  36.0,  0.809,   0.5878),
            ("2",  72.0,  0.309,   0.9511),
            ("3", 108.0, -0.309,   0.9511),
            ("4", 144.0, -0.809,   0.5878),
            ("5", 180.0, -1.0,     0.0),
            ("6", 216.0, -0.809,  -0.5878),
            ("7", 252.0, -0.309,  -0.9511),
            ("8", 288.0,  0.309,  -0.9511),
            ("9", 324.0,  0.809,  -0.5878),
            ("0",   0.0,  1.0,     0.0),
        ]

        var slots: [KeySlot] = []
        for (i, (char, angle, x, y)) in innerData.enumerated() {
            var slot = KeySlot(letter: char, ring: .inner, index: i,
                               angleDeg: angle,
                               normalizedPosition: CGPoint(x: x, y: y))
            slot.angularWidthDeg = 36.0
            slots.append(slot)
        }

        // Outer ring: brackets, math/special, currency
        // Upper segment: [ ] { } < > % ^ ~
        // Lower segment: _ ` | \ $ € £ ¥ °
        let outerSymbols: [Character] = ["[", "]", "{", "}", "<", ">", "%", "^", "~",
                                          "_", "`", "|", "\\", "$", "\u{20AC}", "\u{00A3}", "\u{00A5}", "\u{00B0}"]
        let letterSlots = makeSlots().filter { $0.ring == .outer }
        for (i, ls) in letterSlots.enumerated() {
            let slot = KeySlot(letter: outerSymbols[i], ring: .outer,
                               index: innerData.count + i,
                               angleDeg: ls.angleDeg,
                               normalizedPosition: ls.normalizedPosition,
                               angularWidthDeg: ls.angularWidthDeg)
            slots.append(slot)
        }

        return slots
    }

    // MARK: - Screen coordinate conversion

    /// Compute scale factor and center for a given keyboard view size.
    /// The outer ring edge should fit within the view with some padding.
    static func computeLayout(viewSize: CGSize) -> (center: CGPoint, scale: CGFloat) {
        let center = CGPoint(x: viewSize.width / 2.0, y: viewSize.height / 2.0)
        // Scale to fit the main two rings; arc buttons sit just outside
        let availableRadius = min(viewSize.width, viewSize.height) / 2.0 - 20.0
        let scale = availableRadius / (outerWedgeRMax + 0.1)
        return (center, scale)
    }

    /// Apply center and scale to convert normalized positions to screen coordinates.
    /// Note: y is flipped because iOS y-axis points down.
    static func applyScreenPositions(slots: inout [KeySlot], center: CGPoint, scale: CGFloat) {
        for i in slots.indices {
            let norm = slots[i].normalizedPosition
            slots[i].screenPosition = CGPoint(
                x: center.x + norm.x * scale,
                y: center.y - norm.y * scale  // flip y for iOS
            )
        }
    }
}
