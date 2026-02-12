# Lessons Learned — Better Keyboard v1 → v2 Rewrite

## The Bug

After implementing a round of visual polish and UX improvements (wedge-shaped keys, arc buttons, cursor mode, dark mode), every swipe on the keyboard triggered iOS's "switch keyboard" behavior. The keyboard was unusable — any finger movement that wasn't a short inner-ring tap would immediately switch away to the next keyboard.

## Timeline

1. **Working state:** Swipe-to-type functional, column buttons on left, prediction bar at top, simple raw touch handling, height 320pt.
2. **Plan implemented:** Switched to arc buttons on the ring, added cursor mode with timers, removed prediction bar, changed height to 290pt, added various touch handling complexity.
3. **Bug appeared:** Every swipe triggered keyboard switching.
4. **Debugging spiral (~2 sessions):** Tried ~12 different fixes, none fully worked.
5. **Nuclear rewrite:** Stripped everything back to minimal clean code. Worked immediately.

## What We Tried (and what happened)

| Approach | Result |
|----------|--------|
| Disable UISwipe/UIPanGestureRecognizers on ancestor views | No effect |
| Remove ALL gesture recognizers from ancestor views | Inner ring partially worked |
| UILongPressGestureRecognizer(minimumPressDuration: 0) as touch claimer | Inner ring improved, outer still broken |
| Move all touch handling into GR action (cancelsTouchesInView=true) | Same — inner works, outer broken |
| Custom ImmediateTouchGestureRecognizer subclass | No improvement |
| isExclusiveTouch = true | No improvement |
| point(inside:with:) override | No improvement |
| needsInputModeSwitchKey = false | Made it WORSE — instant switch on activation |
| Height change 290→320 | Layout broke (zoomed in, buttons offscreen) |
| Revert to raw touchesBegan/Moved/Ended overrides (keeping all other changes) | Still broken |
| **Full rewrite — minimal clean code** | **Fixed immediately** |

## What Actually Fixed It

A clean rewrite of the three core files (KeyboardViewController, RingView, TouchRouter) that:
- Removed ~475 lines of accumulated complexity
- Used raw `touchesBegan/Moved/Ended/Cancelled` (same as original working code)
- Removed all gesture recognizer machinery
- Removed cursor mode, center hold timers, debug labels, system GR stripping
- Kept the same visual design (arc buttons, wedge keys, dark theme)

The rewrite compiled and worked on first deploy.

## What We Still Don't Know

**We never identified the exact root cause.** The bug could have been caused by:
- Gesture recognizer competition with system keyboard-switch detection
- Timer-based cursor mode interfering with touch lifecycle
- System GR removal being counterproductive (removing things the system needs)
- Subtle interaction between multiple "fixes" making things worse
- Something entirely different that the accumulated complexity obscured

This is an important lesson: **when you can't isolate the cause, sometimes the fastest path is a clean rewrite rather than more debugging.**

## Key Takeaways

### 1. Complexity is the enemy of debugging
The original bug might have been a one-line fix. But by the time we'd added UILongPressGestureRecognizer, system GR stripping, debug labels, custom GR subclasses, and various flag toggles, there were too many interacting variables to isolate anything. Each "fix" potentially introduced new interactions.

### 2. Know when to stop patching and start over
After ~12 attempted fixes across 2 sessions, none of which fully worked, the right move was stepping back. The rewrite took about 15 minutes and worked immediately. The debugging took hours and produced nothing usable.

**Rule of thumb:** If you've tried 3-4 substantially different approaches and none work, consider whether a clean rewrite of the affected code would be faster than continuing to debug.

### 3. Save your working state before making changes
We had a working keyboard before starting the visual polish plan. If we'd committed that as a proper checkpoint and made incremental commits for each change, we could have bisected to find exactly which change broke things. Instead, all the changes were applied in one session, making it impossible to isolate.

### 4. iOS keyboard extensions are a hostile environment
The system adds private gesture recognizers, monitors touches at the window level, and has keyboard-switching behavior that operates outside the normal UIKit touch handling chain. This makes keyboard extensions uniquely fragile — small changes to touch handling can have outsized effects.

### 5. Simple code is more robust than clever code
The working code uses plain `touchesBegan/Moved/Ended` overrides — the simplest possible touch handling in UIKit. The broken code used UILongPressGestureRecognizer with carefully tuned properties, custom GR subclasses, delegate methods, and dynamic system GR removal. The simple approach worked; the clever approach didn't.

### 6. "Lessons learned" from debugging may be wrong
During the debugging process, we formed several hypotheses:
- "Gesture recognizers can't be used in keyboard extensions"
- "System GR removal is essential"
- "needsInputModeSwitchKey must stay true"

Some of these may be true. Some may not. The clean rewrite worked without testing these hypotheses — it just avoided the patterns that were problematic. Be skeptical of debugging conclusions that weren't rigorously validated.

## Files

- `current-state-snapshot.txt` — Full snapshot of v1 code (broken state) for reference
- `pre-switch-state.txt` — Reconstructed code from before the bug appeared
- `SPEC-v2.md` — Comprehensive specification used for the rewrite
