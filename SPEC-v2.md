# Better Keyboard v2 — Implementation Specification

**Purpose:** One-thumb swipe-typing keyboard for iOS, using a circular ring layout optimized via simulated annealing for bigram separation and ergonomic thumb reach.

**Stack:** Swift / UIKit (iOS Keyboard Extension), Python (optimizer — already complete, don't touch)

**Reference files (read-only, do NOT modify):**
- `current-state-snapshot.txt` — full code snapshot of v1 attempt
- `pre-switch-state.txt` — earlier checkpoint (also had issues)
- `custom-swipe-keyboard.md` — original vision doc

---

## 1. Project Structure

```
BetterKeyboard/
  project.yml                    (XcodeGen, generates .xcodeproj)
  BetterKeyboardApp/             (Container app — minimal, "enable keyboard" instructions)
    AppDelegate.swift
    MainViewController.swift
    Assets.xcassets/
  KeyboardExtension/             (The actual keyboard)
    KeyboardViewController.swift (UIInputViewController — text insertion, shift, autocorrect)
    Layout/
      KeySlot.swift              (Data model for one key position)
      RingLayoutConfig.swift     (Hardcoded optimizer output + geometry constants)
    Rendering/
      RingView.swift             (Main UIView — layers, buttons, touch routing)
      KeyCapLayer.swift          (CAShapeLayer for one key — bracket outline + text)
      SwipeTrailLayer.swift      (CAShapeLayer showing finger trail during swipe)
    Input/
      TouchRouter.swift          (Classifies touches → tap/swipe/backspace/space/etc.)
      SwipeTracker.swift         (Tracks which keys the finger passes during a swipe)
      SwipeDecoder.swift         (Matches visited key sequence → dictionary word)
    Dictionary/
      WordDictionary.swift       (Loads words.txt, indexes by first-last letter pair)
      words.txt                  (~10k words, frequency-ordered, one per line)
    Utilities/
      GeometryHelpers.swift      (Distance, angle, nearest-key, letter frequency table)
```

Build: `xcodegen generate && xcodebuild -scheme BetterKeyboardApp`
Bundle IDs: `com.jacobdetwiler.BetterKeyboard` / `.keyboard`

---

## 2. Ring Geometry (proven — carry forward exactly)

### 2.1 Dual-Ring Layout

- **Inner ring:** 8 keys at normalized radius `1.0`
- **Outer ring:** 18 keys at normalized radius `2.2`
- **Two 36-degree gaps:**
  - Left gap centered at 180° → backspace zone
  - Right gap centered at 0° → space zone
- **Usable arc:** 288° total (two 144° segments: 18°→162° and 198°→342°)

### 2.2 Key Arrangement (from optimizer)

Inner ring (highest-frequency letters):
```
H(36°) N(72°) S(108°) T(144°) | gap | E(216°) A(252°) I(288°) O(324°)
```

Outer ring (18 keys, rare letters toward bottom-right):
```
B(26°) V(42°) M(58°) R(74°) L(90°) W(106°) C(122°) D(138°) F(154°)
| gap |
G(206°) P(222°) U(238°) Y(254°) K(270°) J(286°) Q(302°) Z(318°) X(334°)
```

### 2.3 Coordinate Convention

- Angles use **math convention**: 0° = right, counter-clockwise positive
- iOS y-axis is flipped (down = positive), so screen angles negate: `screenAngle = -mathAngle`
- Normalized positions stored as (x, y) where y follows math convention (up = positive)
- `applyScreenPositions` flips y: `screenY = center.y - norm.y * scale`

### 2.4 Wedge Geometry

Each key occupies a wedge-shaped region:
- Inner keys: 36° wide, radial range `0.6` → `1.6` (normalized)
- Outer keys: 16° wide, radial range `1.6` → `2.35` (normalized)
- Inner and outer wedges share the boundary at `1.6` (no gap)
- 1° angular inset between adjacent keys

### 2.5 Scale Computation

```
availableRadius = min(viewWidth, viewHeight) / 2 - 20
scale = availableRadius / (outerWedgeRMax + 0.1)    // outerWedgeRMax = 2.35
center = (viewWidth / 2, viewHeight / 2)
```

Screen position of a key: `(center.x + norm.x * scale, center.y - norm.y * scale)`

---

## 3. Visual Design

### 3.1 Theme

- Background: pure black (`#000000`)
- Key brackets: dim gray (`rgb(89,89,89)` / white 0.35)
- Key text: white
- Ring arcs: subtle dashed stroke (white 0.25, lineWidth 0.5, dash [4,6])
- Backspace zone: faint red fill (`systemRed` at 8% opacity)
- Space zone: faint glow fill (glow color at 4% opacity)
- Center dot: dim gray fill (white 0.15)
- All zone outlines: very subtle (white 0.25 at 30% opacity)

### 3.2 Accent / Glow Color

Hot pink: `UIColor(red: 1.0, green: 0.1, blue: 0.55, alpha: 1.0)`

Used for: swipe trail, key highlights, active shift indicator, center cursor glow.

### 3.3 Key Cap Rendering

Each key is a `CAShapeLayer` with:
- Two bracket arms (like `[ ]`) at the angular edges of the wedge
- Bracket spans ~55% of the half-angle on each side
- Bracket has both radial (inner↔outer edge) and arc (along ring) extent
- Text layer centered in the wedge, rotated radially (upright on both halves)
- Inner ring text: 16pt, outer ring text: 13pt

### 3.4 Highlight State

When a key is the current swipe target:
- Bracket stroke → glow color
- Text → glow color
- Shadow glow: radius 10, opacity 0.9
- Pulse animation: scale 1.0 → 1.25 → 1.0 over 0.3s

### 3.5 Swipe Trail

A `CAShapeLayer` that draws the finger path during a swipe:
- Glow color at 80% opacity, lineWidth 2.5, round caps/joins
- Shadow glow: radius 8, opacity 0.9
- Points thinned at 200 (stride by 2)
- Cleared on touch end

---

## 4. Input Behavior

### 4.1 Tap on a Letter Key

- Touch starts near a key, doesn't move more than 15pt, touch ends
- Insert the letter (uppercased if shift is active, then deactivate shift)

### 4.2 Swipe to Type a Word

- Touch starts anywhere on the ring, finger moves across multiple keys
- The sequence of keys visited is recorded (proximity-based, not strict hit-test)
- On touch end, the visited key sequence is decoded against the dictionary
- The best-matching word is inserted (with smart spacing)

### 4.3 Space

- Tap the right gap zone (0° ± 18°, outer ring radial range) → insert space
- Tap center zone (within 30pt of center) → insert space
- Double-space → delete the space, insert ". " (period + space)

### 4.4 Backspace

- Tap the left gap zone (180° ± 18°, outer ring radial range) → delete one character
- Swipe left from backspace zone → delete entire word (skip trailing spaces, then delete to previous space)

### 4.5 Shift

- Button tap toggles shift state
- Auto-shift activates at: start of input, after `. `, `! `, `? `, `\n`
- Shift applies to first letter only (tap → uppercase letter; swipe → capitalize first letter of word)
- After applying shift, auto-deactivate

### 4.6 Return

- Button tap → insert `\n`

### 4.7 Punctuation

- Button taps for common punctuation: `.` `,` `'` `?` `!`
- Smart punctuation: if text before cursor ends with space, delete the space before inserting `. ? ! ,`

### 4.8 Auto-Corrections

- Standalone "i": after inserting a space, if text before cursor is `" i "` → replace with `" I "`. Also handles `"i "` at start of input.

### 4.9 Symbol/Number Mode

- Toggle button switches between letter layout and symbol layout
- Symbol layout: 10 digits on inner ring (36° spacing, fills gaps), 18 symbols on outer ring
- Same wedge geometry, just different characters

### 4.10 Cursor Mode (stretch goal — implement last)

- Hold center zone for 1.5s → enter cursor mode
- Drag left/right → move cursor character by character
- Visual feedback: glow builds during hold, pulse on activation, bright glow while active

### 4.11 Center-to-Gap Directional Swipes (stretch goal)

- Swipe from center leftward (no keys visited) → delete word
- Swipe from center rightward (no keys visited) → jump to end of text

---

## 5. Swipe Tracking

### 5.1 Key Proximity Detection

During a swipe, check which key the finger is nearest to:
- Use frequency-weighted distance: `score = letterFrequency / distance^2`
- Max detection radius: 26pt (swipe proximity threshold), 44pt (tap proximity threshold)
- Only add a key to the visited list if it's different from the last visited key

### 5.2 Radial Velocity Suppression

When swiping outward from inner to outer ring, the finger passes through inner keys. Suppress inner-ring key registrations when radial velocity > 4 pt/sample (moving outward fast).

### 5.3 Double Letter Detection (Loop)

To type a double letter (e.g., "ll"), the user draws a small loop/circle over that key:
- Track cumulative angle change of finger movement direction
- When cumulative turn exceeds 300° within a 20-sample window → register the current key again

### 5.4 Tail Trimming

Swipes often overshoot the last intended key. Try matching with 0, 1, or 2 keys trimmed from the end. Trimmed versions get a penalty of 6 points per dropped key.

---

## 6. Swipe Decoding (Word Matching)

### 6.1 Candidate Selection

Given the visited key sequence `[K1, K2, ..., Kn]`:
1. First letter = K1, last letter = Kn (or Kn-1, Kn-2 with tail trimming)
2. Look up all dictionary words starting with that letter and ending with that letter
3. Filter to words with length in range `2...visitedCount`

### 6.2 Subsequence Matching

A word matches if its letters appear as a subsequence of the visited keys:
- Collapse consecutive duplicate letters in the word (e.g., "sloppy" → "slopy")
- Greedy left-to-right scan: for each letter in the word, find the first matching visited key starting from the last match position
- If all letters found → it's a match

### 6.3 Scoring (lower = better)

- **Gap penalty:** `totalSkippedKeys * 3.0` (fewer unmatched keys between matches = better)
- **Span penalty:** `(1 - matchSpan/visitedCount) * 30.0` (match should cover most of the visited sequence)
- **Length bonus:** `-wordLength * 2.0` (prefer longer words — more intentional)
- **Frequency penalty:** `frequencyRank * 0.02` (prefer common words)
- **Trim penalty:** `trimmedKeys * 6.0` (prefer untrimmed matches)

### 6.4 Contractions

Map apostrophe-stripped forms to contracted spellings (e.g., "dont" → "don't"). Contractions get a -5 score bonus unless they're ambiguous (e.g., "well" could be the word "well" or "we'll").

### 6.5 No Gibberish

If no dictionary word matches, return nil. Don't insert random text.

---

## 7. Button Layout

### 7.1 Buttons Needed

- **Shift** (⇧) — toggles shift state
- **123/ABC** — toggles symbol mode
- **Return** (↵) — inserts newline
- **Punctuation:** `.` `,` `'` `?` `!`

### 7.2 Placement

Buttons go OUTSIDE the ring area. Two approaches that have worked:

**Option A — Column layout (proven in pre-switch state):**
Two columns on the left side: control buttons (shift, 123, return) in a far-left column, punctuation buttons in a near-ring column. Both centered vertically. Uses SF Symbols for icons.

**Option B — Arc layout (current):**
Punctuation buttons arrayed around the left gap zone (150°-210°), function buttons around the right gap zone (345°-15°), at radius `outerWedgeRMax + 0.80`.

Either is fine. The key constraint: buttons must be UIButton subviews (not CALayers) so they participate in UIKit hit testing.

---

## 8. Prediction Bar (not yet implemented in working state)

- 36pt tall bar across the top of the keyboard
- 3 UIButton subviews showing word suggestions
- After space: show top-frequency words from dictionary
- Mid-word: show prefix-matched completions
- Tap a prediction → delete current partial word, insert predicted word + space
- When present, shift ring center down by `predictionBarHeight / 2`

---

## 9. Keyboard View Configuration

- Height: 290pt (`.defaultHigh` priority constraint)
- RingView fills the entire keyboard view (all edges pinned)
- `viewWillLayoutSubviews` triggers ring layout recalculation
- Rendering: entirely CAShapeLayer tree (no Auto Layout for keys, no UILabels on the ring)
- All layer positions computed geometrically from center + scale

---

## 10. iOS Keyboard Extension Constraints

### 10.1 Notes from v1 Debugging (unconfirmed — treat as observations, not rules)

- Setting `needsInputModeSwitchKey = false` caused instant keyboard switching in one test — but this may have been interacting with other issues at the time.
- Gesture recognizer-based touch handling appeared to conflict with system keyboard-switch detection. Raw `touchesBegan/Moved/Ended/Cancelled` is simpler and is what the original working code used.
- System gesture recognizers exist on ancestor views (`_UIHostedWindow`, `UIDropShadowView`). Disabling UISwipe/UIPan types on the ancestor chain was present in the original working code.
- **Memory is limited** in keyboard extensions. Keep dictionary small (~10k words).
- **Bundle access:** Use `Bundle(for: type(of: self))` not `Bundle.main` for extension resources.

### 10.2 Text Insertion API

All text operations go through `textDocumentProxy`:
- `insertText(_:)` — insert text at cursor
- `deleteBackward()` — delete one character before cursor
- `adjustTextPosition(byCharacterOffset:)` — move cursor
- `documentContextBeforeInput` / `documentContextAfterInput` — read surrounding text

---

## 11. Dictionary

- `words.txt`: ~10k English words, one per line, ordered by frequency (most common first)
- Indexed at load time by first-last letter pair for fast candidate lookup: `"t-e" → ["the", "there", ...]`
- Frequency rank = line number (0 = most common)
- Already exists and works — carry forward unchanged

---

## 12. Implementation Order

1. **Skeleton:** KeyboardViewController + empty RingView, verify it loads as keyboard extension
2. **Layout geometry:** KeySlot, RingLayoutConfig, ring arc drawing, key cap rendering
3. **Tap input:** Raw touch handling → nearest key detection → letter insertion
4. **Swipe input:** SwipeTracker (key visit tracking) → SwipeDecoder (word matching) → word insertion
5. **Gap zones:** Backspace tap/swipe, space tap, double-space-to-period
6. **Buttons:** Shift, return, 123, punctuation (as UIButton subviews)
7. **Polish:** Auto-shift, auto-correct "i", smart punctuation spacing, swipe trail
8. **Stretch:** Prediction bar, cursor mode, center directional swipes

---

## 13. What to Preserve vs. Rewrite

### Preserve exactly (copy from snapshot):
- `RingLayoutConfig.swift` — proven geometry, optimizer output
- `KeySlot.swift` — simple data model
- `GeometryHelpers.swift` — math utilities
- `SwipeTrailLayer.swift` — visual trail rendering
- `KeyCapLayer.swift` — bracket key rendering
- `WordDictionary.swift` — dictionary loading and indexing
- `SwipeDecoder.swift` — word matching algorithm (fix duplicate "youre" key)
- `words.txt` — dictionary file
- `BetterKeyboardApp/` — container app (unchanged)

### Rewrite from scratch:
- `RingView.swift` — the main view (touch handling, layer management, buttons)
- `TouchRouter.swift` — touch classification and routing
- `SwipeTracker.swift` — key visit tracking during swipes (can largely reuse, but review)
- `KeyboardViewController.swift` — the controller (text insertion, shift state, autocorrect)

### Delete:
- `ImmediateTouchGestureRecognizer.swift` — debugging artifact, not needed
- `TapHandler.swift` — empty placeholder, never used
