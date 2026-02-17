import UIKit

/// Touch routing for grid keyboard layouts.
/// Simpler than the ring's TouchRouter — no center zone, no angular gaps, no cursor mode.
/// Special keys (shift, backspace, space, return) are UIButtons handled outside this router.
class GridTouchRouter {

    enum Mode {
        case none
        case keyTap(KeySlot)   // near a key: tap = letter, drag = swipe
        case gridSwipe         // finger is swiping across the grid
    }

    private weak var gridView: GridKeyboardView?
    private var mode: Mode = .none
    private var startPoint: CGPoint = .zero
    private var swipeTracker: SwipeTracker?

    private let swipeThreshold: CGFloat = 15.0
    /// Hit test padding beyond key bounds (pts)
    private let hitPadding: CGFloat = 4.0
    /// SwipeTracker proximity for grid (tighter than ring's 26pt)
    private let gridProximityThreshold: CGFloat = 20.0

    init(gridView: GridKeyboardView) {
        self.gridView = gridView
    }

    // MARK: - Touch events

    func touchBegan(_ point: CGPoint, timestamp: TimeInterval) {
        guard let gridView = gridView else { return }
        startPoint = point

        let slots = gridView.slots

        // Find nearest key by rectangular hit test
        if let nearest = hitTestKey(point, in: slots) {
            mode = .keyTap(nearest)
            gridView.highlightKey(at: nearest.index)
            swipeTracker = SwipeTracker(slots: slots, proximityThreshold: gridProximityThreshold)
            swipeTracker?.begin(at: point, timestamp: timestamp, initialSlot: nearest)
            gridView.swipeTrail.beginTrail(at: point)
            return
        }

        // Started outside any key — begin as swipe anyway (might drag onto keys)
        swipeTracker = SwipeTracker(slots: slots, proximityThreshold: gridProximityThreshold)
        swipeTracker?.begin(at: point, timestamp: timestamp, initialSlot: nil)
        gridView.swipeTrail.beginTrail(at: point)
        mode = .gridSwipe
    }

    func touchMoved(_ point: CGPoint, timestamp: TimeInterval) {
        guard let gridView = gridView else { return }

        switch mode {
        case .keyTap:
            if GeometryHelpers.distance(startPoint, point) > swipeThreshold {
                mode = .gridSwipe
                gridView.unhighlightAllKeys()
            }
            swipeTracker?.addSample(point, timestamp: timestamp)
            gridView.swipeTrail.addPoint(point)
            gridView.unhighlightAllKeys()
            if let current = swipeTracker?.currentSlot {
                gridView.highlightKey(at: current.index)
            }

        case .gridSwipe:
            swipeTracker?.addSample(point, timestamp: timestamp)
            gridView.swipeTrail.addPoint(point)
            gridView.unhighlightAllKeys()
            if let current = swipeTracker?.currentSlot {
                gridView.highlightKey(at: current.index)
            }

        case .none:
            break
        }
    }

    func touchEnded(_ point: CGPoint) {
        guard let gridView = gridView else { return }
        defer { cleanup() }

        switch mode {
        case .keyTap(let slot):
            if GeometryHelpers.distance(startPoint, point) <= swipeThreshold {
                gridView.delegate?.keyboardLayout(gridView, didTapLetter: slot.letter)
            } else {
                finalizeSwipe()
            }

        case .gridSwipe:
            finalizeSwipe()

        case .none:
            break
        }
    }

    func touchCancelled() {
        cleanup()
    }

    // MARK: - Hit testing

    /// Rectangular hit test with padding. Returns the slot whose key rect contains the point.
    private func hitTestKey(_ point: CGPoint, in slots: [KeySlot]) -> KeySlot? {
        for slot in slots {
            let w = (slot.keyWidth ?? GridLayoutConfig.baseKeyWidth) + hitPadding * 2
            let h = (slot.keyHeight ?? GridLayoutConfig.baseKeyHeight) + hitPadding * 2
            let rect = CGRect(x: slot.screenPosition.x - w / 2,
                              y: slot.screenPosition.y - h / 2,
                              width: w, height: h)
            if rect.contains(point) {
                return slot
            }
        }
        return nil
    }

    // MARK: - Private

    private func finalizeSwipe() {
        guard let gridView = gridView,
              let tracker = swipeTracker else { return }
        let keys = tracker.finalize()
        if !keys.isEmpty {
            gridView.delegate?.keyboardLayout(gridView, didSwipeWord: keys)
        }
    }

    private func cleanup() {
        gridView?.unhighlightAllKeys()
        gridView?.swipeTrail.endTrail()
        swipeTracker = nil
        mode = .none
    }
}
