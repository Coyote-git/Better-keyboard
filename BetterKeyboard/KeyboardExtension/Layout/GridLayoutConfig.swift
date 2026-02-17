import CoreGraphics

/// Which grid layout to display.
enum GridLayoutName: String, CaseIterable {
    case qwerty
    case dvorak
    case workman
    case coyote
}

/// Static geometry and letter placement for ortholinear grid keyboards.
/// All positions are computed from view size — no Auto Layout.
enum GridLayoutConfig {

    // MARK: - Key sizing constants

    /// Target key dimensions (pts). Actual sizes may flex slightly to fill width.
    static let baseKeyWidth: CGFloat = 32
    static let baseKeyHeight: CGFloat = 42
    static let keySpacing: CGFloat = 6

    /// Top strip height for predictions (matches ring layout)
    static let predictionBarHeight: CGFloat = 34
    /// Bottom row height (special keys: 123, cycle, comma, space, period, return)
    static let bottomRowHeight: CGFloat = 42

    // MARK: - Layout definitions (rows of characters)

    /// Returns letter rows for a given layout. Each row is a string of uppercase letters.
    static func rows(for layout: GridLayoutName) -> [String] {
        switch layout {
        case .qwerty:
            return ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
        case .dvorak:
            // Apostrophe replaces semicolon — handled as punctuation in the view
            return ["PYFGCRL", "AOEUIDHTNS", "QJKXBMWVZ"]
        case .workman:
            return ["QDRWBJFUP", "ASHTGYNEOI", "ZXMCVKL"]
        case .coyote:
            // Vertical-cluster layout for two-thumb phone typing.
            // Top-9 letters (ETAOINSHR) all in center columns 3–6.
            // Common bigrams become vertical thumb flicks:
            //   Col 3: S→T (ST)    Col 5: I→N (IN)
            //   Col 6: H→E (HE)   Col 4: R→A
            // TH and ER cross hands for alternation.
            // 10/10/6 gives perfect column alignment across all rows.
            return ["QYFSRIHWPJ", "ZGUTANEMBX", "VDLCOK"]
        }
    }

    // MARK: - Symbol grids

    /// Symbol set 1: numbers top row, common punctuation below
    static let symbolRows1: [String] = [
        "1234567890",
        "-/:;()$&@\"",
        ".,?!'",
    ]

    /// Symbol set 2: less common symbols
    static let symbolRows2: [String] = [
        "[]{}#%^*+=",
        "_\\|~<>\u{20AC}\u{00A3}\u{00A5}\u{2022}",
        ".,?!'",
    ]

    // MARK: - Slot generation

    /// Build KeySlots for a letter layout, computing screen positions from view size.
    /// Rows are vertically stacked below the prediction bar. Shorter rows are centered
    /// within the widest row (ortholinear — columns align, no stagger).
    static func makeSlots(layout: GridLayoutName, viewSize: CGSize) -> [KeySlot] {
        return buildSlots(from: rows(for: layout), viewSize: viewSize)
    }

    /// Build KeySlots for a symbol layout.
    static func makeSymbolSlots(set: Int, viewSize: CGSize) -> [KeySlot] {
        let rows = (set == 1) ? symbolRows1 : symbolRows2
        return buildSlots(from: rows, viewSize: viewSize)
    }

    /// Core slot builder. Takes an array of row strings and computes screen geometry.
    private static func buildSlots(from rows: [String], viewSize: CGSize) -> [KeySlot] {
        guard !rows.isEmpty else { return [] }

        let maxCols = rows.map(\.count).max() ?? 10
        // Compute actual key width to fill the available width evenly
        let totalSpacing = keySpacing * CGFloat(maxCols + 1)
        let keyW = min(baseKeyWidth, (viewSize.width - totalSpacing) / CGFloat(maxCols))
        let keyH = baseKeyHeight

        // Vertical start: below prediction bar
        let topY = predictionBarHeight + keySpacing

        var slots: [KeySlot] = []
        var slotIndex = 0

        for (row, rowStr) in rows.enumerated() {
            let cols = Array(rowStr)
            let rowWidth = CGFloat(cols.count) * keyW + CGFloat(cols.count - 1) * keySpacing
            let rowLeft = (viewSize.width - rowWidth) / 2.0  // center shorter rows

            let y = topY + CGFloat(row) * (keyH + keySpacing) + keyH / 2.0

            for (col, char) in cols.enumerated() {
                let x = rowLeft + CGFloat(col) * (keyW + keySpacing) + keyW / 2.0
                var slot = KeySlot(
                    letter: char,
                    ring: .grid,
                    index: slotIndex,
                    angleDeg: 0,
                    normalizedPosition: .zero,
                    screenPosition: CGPoint(x: x, y: y)
                )
                slot.gridRow = row
                slot.gridCol = col
                slot.keyWidth = keyW
                slot.keyHeight = keyH
                slots.append(slot)
                slotIndex += 1
            }
        }

        return slots
    }

    // MARK: - Special key positions

    /// Compute the Y coordinate for the bottom row of special keys.
    /// Letter rows stack below prediction bar; bottom row sits below the last letter row.
    static func bottomRowY(letterRowCount: Int, viewSize: CGSize) -> CGFloat {
        let topY = predictionBarHeight + keySpacing
        let lettersHeight = CGFloat(letterRowCount) * (baseKeyHeight + keySpacing)
        return topY + lettersHeight + bottomRowHeight / 2.0
    }

    /// Compute the Y for the shift/backspace row (same row as the last letter row).
    static func modifierRowY(letterRowCount: Int, viewSize: CGSize) -> CGFloat {
        let topY = predictionBarHeight + keySpacing
        return topY + CGFloat(letterRowCount - 1) * (baseKeyHeight + keySpacing) + baseKeyHeight / 2.0
    }
}
