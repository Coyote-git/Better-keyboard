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

### 4.7 Punctuation & Smart Spacing

- Button taps for common punctuation: `.` `,` `'` `"` `?` `!`
- Symbol ring taps for non-alphanumeric characters route through the same punctuation
  handler for consistent behavior regardless of input source
- Smart punctuation: if text before cursor ends with space, delete the space before
  inserting `. ? ! , ) ] }`
- **Quote/bracket tracking:** unmatched `"` and `'` counts distinguish opening vs closing:
  - Opening quote/bracket: leave preceding space, skip space before next swiped word
  - Closing quote/bracket: eat trailing space so it hugs the word
  - Apostrophe detection: `'` preceded by a letter with no unmatched quotes → apostrophe,
    not a quote (contraction toggle takes priority when a match exists)
  - Counts reverse correctly on backspace; word-delete tracks per character
  - Counts reset on keyboard appearance (new field / reopen)
- **Word-delete boundaries:** backswipe stops at standalone quotes and brackets instead of
  deleting through them; mid-word apostrophes (preceded by a letter) are deleted as part
  of the word

### 4.8 Auto-Corrections

- Standalone "i": after inserting a space, if text before cursor is `" i "` → replace with `" I "`. Also handles `"i "` at start of input.

### 4.9 Symbol/Number Mode

- Three-state toggle: Letters → Symbol Set 1 → Symbol Set 2
- **Symbol Set 1:** 10 digits on inner ring (36° spacing, fills gaps), 18 common symbols on outer ring
  - Upper (left→right): `( ) # @ & ? ! , .`
  - Lower (left→right): `- + = / * : ; " '`
- **Symbol Set 2:** Same 10 digits, 18 brackets/currency/special on outer ring
  - Upper (left→right): `[ ] { } < > % ^ ~`
  - Lower (left→right): `` _ ` | \ $ € £ ¥ ° ``
- Toggle flow: shift button becomes "#+=", "123" in symbol modes; "ABC" always returns to letters
- Same wedge geometry, just different characters

### 4.10 Cursor Mode

- Hold center zone for 1s → enter cursor mode
- Drag left/right → move cursor character by character
- Visual feedback: glow builds during hold, pulse on activation, bright glow while active

### 4.11 Center-to-Gap Directional Swipes

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

### 7.1 Buttons

- **Shift** (⇧) / **#+=** / **123** — context-dependent (letters: shift, symbols1: toggle to set 2, symbols2: toggle to set 1)
- **123** / **ABC** — toggles between letters and symbol mode
- **Return** (↵) — inserts newline
- **Punctuation:** `.` `,` `'` `"` `?` `!`
- **Theme toggle** — top-left corner, cycles through themes
- **Dismiss** — top-right corner, dismisses keyboard

### 7.2 Placement

Arc layout: punctuation buttons along the left arc (150°-210°), function buttons along the right arc (345°-15°), at radius `outerWedgeRMax + 0.80`. Theme and dismiss buttons in top corners.

Buttons are UIButton subviews (not CALayers) so they participate in UIKit hit testing.

---

## 8. Prediction Bar

- 36pt tall bar across the top of the keyboard (PredictionBarView)
- 3 UIButton subviews showing word suggestions
- Three modes:
  - **After space (suggestion):** show top-frequency words from dictionary
  - **Mid-word (completion):** show prefix-matched completions
  - **After swipe (alternatives):** show alternative swipe decode results; tap replaces last word
- Tap a prediction → insert word (or replace, depending on mode)
- Pinned above RingView via Auto Layout

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

## 12. Completed (v2 rewrite)

All core features from the original implementation plan are done:

- [x] Skeleton, layout geometry, key cap rendering
- [x] Tap input, swipe input, gap zones (backspace/space)
- [x] Buttons (shift, 123/ABC, return, punctuation)
- [x] Auto-shift, auto-correct "i", smart punctuation spacing
- [x] Prediction bar (3 suggestions: prefix completions mid-word, frequency after space, swipe alternatives)
- [x] Cursor mode (hold center 1s → drag to move cursor)
- [x] Center directional swipes (center→left = delete word, center→right = jump to end)
- [x] Symbol mode with two sets (common symbols + brackets/currency/special)
- [x] Three themes (dark, light, midnight) with live cycling
- [x] `"` on punctuation button bar
- [x] Smart quote/bracket tracking (open vs close counting, proper nesting)
- [x] Unified punctuation routing (symbol ring taps get same smart spacing as buttons)
- [x] No leading space after opening quote/bracket on swipe
- [x] Closing quote/bracket eats trailing space
- [x] Word-delete respects quote/bracket boundaries
- [x] SwipeDecoder `decodeTopN` for prediction bar alternatives
- [x] First word in field already handled correctly (no spurious leading space)

---

## 13. Roadmap

### 13.1 Polish

**Prediction bar styling:**
- Match theme color palette (currently default system button look)
- Smaller font, smaller buttons — prediction bar should be unobtrusive
- Consider hiding theme/dismiss buttons behind a long-press or moving them elsewhere
  to reclaim vertical space

**Smoother comet trail:**
Current trail is segment-by-segment with abrupt clearing. Target behavior:
- Each pixel of the trail fades out individually, exactly 1s after it was drawn
- Creates a smooth "comet tail" effect where the trail appears to erase itself
  at the same speed it was drawn
- Likely needs a time-stamped point buffer and a CADisplayLink-driven fade,
  rather than the current single-path approach in SwipeTrailLayer

**Cursor mode improvements:**
- Current implementation works but feels imprecise (TBD on specifics)
- Possible improvements: visual cursor position indicator, variable speed based on
  drag distance from center, haptic ticks per character moved

### 13.2 Features

**Profanity / forbidden words:**
- Add swear words and other commonly-filtered words to the dictionary
- Gated behind a toggle in settings (default OFF for App Store compliance)
- Separate word list file (e.g., `words-profanity.txt`) loaded conditionally

**Settings menu:**
- Theme customizer: let users recolor existing themes (accent color, background, key color)
- Liquid Glass theme: translucent blur-backed keys matching iOS 26 design language
  (UIVisualEffectView / CABackdropLayer underneath the ring)
- Profanity dictionary toggle (see above)
- Stored via UserDefaults in shared App Group container

**Learning dictionary:**
- Track words the user types through the keyboard, boost their frequency ranking
- Store word frequency counts in UserDefaults (shared App Group)
- On startup, merge learned frequencies with the base dictionary
- iOS sandbox prevents scraping Messages or other app history — can only learn
  from words typed through this keyboard
- Privacy-first: all data stays on-device, no network calls

**Alternative keyboard layouts:**
- Add traditional grid-based layouts as an option alongside the ring:
  QWERTY, Dvorak, Workman, and a custom "Coyote" layout
- Coyote layout concept: optimized for two-thumb phone typing with most-used keys
  centered on natural thumb positions (roughly where S-D and J-K sit on QWERTY)
  — may end up resembling Workman, needs analysis
- Requires a separate grid rendering path (new UIView subclass or RingView mode)
- Layout switching via settings or long-press on mode button
- Swipe typing should work on grid layouts too (same SwipeDecoder, different geometry)

### 13.3 App Store

- [ ] App icon design
- [ ] Privacy policy (required — keyboard has Full Access capability even if unused)
- [ ] App Store screenshots and description
- [ ] Review guideline compliance check (keyboard extension rules)
- [ ] TestFlight beta round
