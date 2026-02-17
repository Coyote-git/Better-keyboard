# Better Keyboard

A custom iOS keyboard with swipe-to-type, featuring a unique circular ring layout alongside traditional grid layouts (QWERTY, Dvorak, Workman, and a custom "Coyote" layout).

## Layouts

**Ring** — A dual-ring circular layout where 26 letters are arranged around two concentric rings. Key placement was optimized via simulated annealing to maximize distance between common bigrams, making swipe paths more distinct and accurate. High-frequency letters (E, T, A, O, I, N, S, H) sit on the inner ring for quick thumb reach.

**QWERTY / Dvorak / Workman** — Standard grid layouts with ortholinear key positioning (no row stagger). Swipe-to-type works on all of them.

**Coyote** — A custom vertical-cluster layout designed for phone typing. The 9 most common letters are grouped in the center columns so common bigrams (HE, IN, ST) become vertical thumb movements rather than horizontal reaches.

```
Ring:            Grid (Coyote):
    N                Q Y F S R I H W P J
  S   H              Z G U T A N E M B X
T       B                V D L C O K
  E   O
    A I
```

Users cycle between all five layouts with a keyboard button. Last-used layout persists across sessions.

## Features

- **Swipe-to-type** with dictionary matching and word predictions
- **Tap typing** on all layouts
- **Smart punctuation** — auto-spacing, quote/bracket balancing
- **Auto-shift** after sentence-ending punctuation
- **Auto-correct** (standalone "i" → "I", common contractions)
- **Symbol mode** — two sets of symbols/numbers
- **Cursor mode** (ring layout) — hold center, drag to move cursor
- **Three themes** — dark, light, midnight

## Project Structure

```
optimizer/          Python simulated annealing for ring letter placement
BetterKeyboard/
  project.yml       XcodeGen project definition
  BetterKeyboardApp/    Container app (enable-keyboard instructions)
  KeyboardExtension/    The keyboard
    Layout/         Key positions, layout protocols, geometry
    Rendering/      Ring + grid views, key cap layers, swipe trail
    Input/          Touch routing, swipe tracking, word decoding
    Dictionary/     Word list + frequency-indexed lookup
```

## Building

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen    # if not already installed
cd BetterKeyboard
xcodegen generate
open BetterKeyboard.xcodeproj
```

Build the `BetterKeyboardApp` scheme, then enable the keyboard in Settings → General → Keyboard → Keyboards → Add New Keyboard.

## How It Works

### Swipe Decoding

During a swipe, the keyboard tracks which keys the finger passes near. On lift, the visited key sequence is matched against a ~10k word dictionary using subsequence matching with scoring based on gap penalty, span coverage, word frequency, and length. The ring layout's bigram-optimized placement means swipe paths for different words are more geometrically distinct than on QWERTY.

### Ring Geometry

The ring uses normalized polar coordinates converted to screen positions at layout time. Two 36° gaps at 0° (space) and 180° (backspace) divide the ring into upper and lower arcs. Keys occupy wedge-shaped hit regions with inner/outer radial boundaries.

### Grid Geometry

Grid layouts compute key positions from view width — keys are evenly sized, shorter rows are centered, and all columns align vertically (ortholinear). The swipe pipeline is shared between ring and grid; only the proximity threshold differs (26pt ring, 20pt grid).

## Optimizer

The `optimizer/` directory contains a Python simulated annealing optimizer that finds letter placements for the ring layout. It maximizes weighted bigram distances so common letter pairs (TH, HE, IN, etc.) are far apart on the ring, reducing swipe ambiguity.

```bash
cd optimizer
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python run.py
```

## License

This project is not currently licensed for reuse. All rights reserved.
