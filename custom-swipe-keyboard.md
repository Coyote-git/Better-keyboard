# Custom Swipe Keyboard (iOS)

**Status:** Pipeline (moving up priority)
**Effort Estimate:** Tier 1 PoC ~1-2 weeks, Tier 2 usable ~2-4 months
**Stack:** Swift / UIKit (iOS Keyboard Extension), Python (layout optimization tooling)
**Potential Integration:** GifHorse

## Summary

A custom iOS swipe-typing keyboard built from scratch, featuring a circular ring layout optimized for one-handed thumb input. Designed to eventually learn from personal usage patterns for prediction quality that beats generic solutions like GBoard. Core algorithm is geometric path matching (curve comparison / dynamic time warping) against a dictionary — conceptually similar to game dev path collision + scoring. Plus first-party GifHorse integration for commonly used gifs.

## Why

- iOS stock keyboard swipe implementation is objectively bad
- Third-party options (GBoard, SwiftKey) are good but not personalized
- Local-first keyboard trained on YOUR vocabulary and message patterns could outperform generic models for personal use
- Good skill demonstration for vibe coding portfolio
- Fun application of game-dev-adjacent math (geometry, scoring, real-time input processing)
- First-party level GifHorse integration
- Usability / physical therapy thumb swipe patterns (reduce thumb strain for typing or swiping)
- Adjustable positioning and opacity — place the ring at vertical center right side to fix pinky phone-holding strain
- Circular layout optimized for speed and clarity based on direction changes

## Design Concept: Circular Ring Layout

Key insight: on a traditional QWERTY grid, swipe paths cross over tons of unintended letters, creating ambiguity the algorithm has to resolve. On a circular layout, paths between non-adjacent letters curve through the empty center — less collateral letters, cleaner signal, less guesswork.

- **2-3 concentric rings** — inner ring for highest-frequency letters (E, T, A, O, I, N, S, R), outer rings for less common letters
- **Letter arrangement optimized via simulated annealing** against English bigram frequency data — common pairs positioned for minimal travel, uncommon pairs can be far apart
- **Direction changes are the signal** — circular paths naturally produce spikier, more angular traces. More angular = easier to detect intended letters vs pass-throughs. Prioritize direction changes in layout for most common letter pairings — easier to detect going back and forth than rolling
- **Adjustable position + opacity** — user can place the ring wherever is comfortable, not locked to bottom of screen
- **Experiment with half-circle variants** — and traditional swiping vs moving the circle up/down (scrolling) to select at a predetermined point. Selection then becomes muscle memory rather than precision targeting

## Core Technical Challenges

- **Path matching algorithm** — comparing sloppy finger paths against ideal letter-to-letter paths for dictionary words. Dynamic time warping or similar curve comparison.
- **Direction-change detection** — angular/spiky paths on circular layout should give cleaner signal than wobbly straight lines on grid. Leverage this in the matching algorithm.
- **Candidate pruning** — can't brute-force compare against 100k+ words in real time. Trie structures + early elimination based on which keys the path crosses.
- **Fuzzy error tolerance** — accounting for finger size, speed, drift, imprecise swipes. The hard part.
- **Language model** — even basic bigram/trigram prediction ("what word is likely after the previous word") dramatically improves accuracy over pure geometry matching.
- **iOS Keyboard Extension API** — notoriously restrictive. Limited memory, weird lifecycle, second-class citizen compared to Android IME. Expect jank.

## Milestones

0. **Layout optimization** — Python script using simulated annealing + bigram frequency data to generate mathematically optimal circular letter arrangement. First concrete deliverable.
1. **PoC** — circular layout rendered, swipe input capture, basic path matching against small dictionary. "It works but feels bad."
2. **Usable** — proper candidate pruning, fuzzy matching, basic language model, polished UI, one-handed mode, adjustable positioning.
3. **Personalized** — local ML model trained on user's own typing patterns and vocabulary.
4. **GifHorse integration** — first-party gif keyboard layer, commonly used gifs, seamless switching.
5. **Stretch** — custom themes, text expansion, AI-assisted sentence completion via local or API-based LLM. Custom layouts beyond QWERTY/Dvorak — optimized for left or right handed thumb swipe. Half-circle and scroll-select variants.

## References

- Swype (discontinued 2018) — the OG, geometric path matching pioneer
- GBoard — current best-in-class, backed by Google's language models
- AlterEgo (MIT/startup) — subvocalization input, the far-future version of this problem
- English bigram frequency tables — for layout optimization
- Simulated annealing — optimization algorithm modeled after metalworking heat treatment, used to find optimal letter arrangement
