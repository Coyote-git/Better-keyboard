import UIKit

// MARK: - Delegate protocol (shared by ring and grid views)

/// Actions a keyboard layout view can report to the view controller.
/// Replaces the old RingViewDelegate — same methods, layout-agnostic parameter type.
protocol KeyboardLayoutDelegate: AnyObject {
    func keyboardLayout(_ layout: any KeyboardLayoutView, didTapLetter letter: Character)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didTapSpace: Void)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didTapBackspace: Void)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didSwipeWord keys: [WeightedKey])
    func keyboardLayout(_ layout: any KeyboardLayoutView, didTapShift: Void)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didTapReturn: Void)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didDeleteWord: Void)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didTapPunctuation character: Character)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didMoveCursor offset: Int)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didJumpToEnd: Void)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didTapDismiss: Void)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didSelectPrediction word: String)
    func keyboardLayout(_ layout: any KeyboardLayoutView, didRequestLayoutCycle: Void)
}

// MARK: - Layout view protocol (ring and grid both conform)

/// Shared interface for any keyboard layout view (ring, QWERTY grid, etc.).
/// The view controller talks to this protocol — doesn't know or care which layout is active.
protocol KeyboardLayoutView: AnyObject {
    var delegate: KeyboardLayoutDelegate? { get set }
    var slots: [KeySlot] { get }
    var swipeTrail: SwipeTrailLayer { get }
    var preferredHeight: CGFloat { get }

    func configure(viewSize: CGSize)
    func updatePredictions(_ suggestions: [String])
    func updateShiftAppearance(isShifted: Bool, isCapsLocked: Bool)
    func reapplyTheme()
}
