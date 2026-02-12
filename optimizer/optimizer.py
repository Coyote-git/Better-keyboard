"""
Circular keyboard layout optimizer using simulated annealing.
For swipe typing: MAXIMIZES distance between frequent bigram pairs
(so swipe paths are distinctive) while keeping frequent letters in
easy-to-reach positions and pushing rare letters to bottom-right.
"""

import math
import random
import numpy as np

from bigrams import BIGRAM_FREQ, LETTER_FREQ

LETTERS = list('ABCDEFGHIJKLMNOPQRSTUVWXYZ')


def compute_positions(n_inner=8, n_outer=18, r_inner=1.0, r_outer=2.2,
                      gap_angles=None, gap_width_deg=36.0):
    """
    Compute (x, y) for each slot on a dual-ring layout with optional gaps.

    gap_angles: list of angles (degrees) where gaps are centered.
                Default: [180, 0] — left gap (backspace) and right gap (reserved).
    gap_width_deg: angular width of each gap in degrees.

    Slots are distributed evenly across the remaining non-gap arc.
    Returns list of 26 (x, y) tuples: indices 0..n_inner-1 are inner ring,
    n_inner..25 are outer ring.
    Also returns metadata dict with arc info for visualization.
    """
    if gap_angles is None:
        gap_angles = [180.0, 0.0]

    total_gap = len(gap_angles) * gap_width_deg
    usable_arc = 360.0 - total_gap  # degrees of usable arc

    # Build sorted list of gap boundaries (in degrees, 0=right, CCW)
    # Each gap is centered at its angle and spans gap_width_deg
    gaps = []
    for g in gap_angles:
        half = gap_width_deg / 2.0
        start = (g - half) % 360.0
        end = (g + half) % 360.0
        gaps.append((g, start, end))

    def angle_in_gap(angle_deg):
        """Check if an angle falls inside any gap."""
        for _, gs, ge in gaps:
            if gs < ge:
                if gs <= angle_deg < ge:
                    return True
            else:  # wraps around 0
                if angle_deg >= gs or angle_deg < ge:
                    return True
        return False

    # Build usable arc segments (sorted CCW from right gap end)
    # Right gap: 342°–18°, Left gap: 162°–198°
    # Usable segments: [18°, 162°] and [198°, 342°]
    half = gap_width_deg / 2.0
    right_gap_end = (gap_angles[1] + half) % 360.0    # 18°
    left_gap_start = (gap_angles[0] - half) % 360.0   # 162°
    left_gap_end = (gap_angles[0] + half) % 360.0     # 198°
    right_gap_start = (gap_angles[1] - half) % 360.0  # 342°

    # Two usable segments going CCW from right_gap_end:
    # Segment 1: 18° to 162° (144°)
    # Segment 2: 198° to 342° (144°)
    segments = [
        (right_gap_end, left_gap_start),   # 18° → 162°
        (left_gap_end, right_gap_start),   # 198° → 342°
    ]
    segment_lengths = []
    for s_start, s_end in segments:
        length = (s_end - s_start) % 360.0
        segment_lengths.append(length)

    def distribute_slots(n_slots, radius):
        """Place n_slots evenly in the non-gap arc, properly skipping gaps."""
        spacing = usable_arc / n_slots
        positions = []
        for i in range(n_slots):
            # Position in the abstract usable arc (0 to usable_arc)
            arc_pos = spacing * (i + 0.5)
            # Map to actual angle by walking through segments
            remaining = arc_pos
            abs_angle_deg = None
            for (s_start, s_end), s_len in zip(segments, segment_lengths):
                if remaining <= s_len:
                    abs_angle_deg = (s_start + remaining) % 360.0
                    break
                remaining -= s_len
            if abs_angle_deg is None:
                abs_angle_deg = (segments[-1][0] + remaining) % 360.0
            abs_angle_rad = math.radians(abs_angle_deg)
            x = radius * math.cos(abs_angle_rad)
            y = radius * math.sin(abs_angle_rad)
            positions.append((x, y))
        return positions

    inner_positions = distribute_slots(n_inner, r_inner)
    outer_positions = distribute_slots(n_outer, r_outer)

    all_positions = inner_positions + outer_positions

    # Store metadata for visualization and iOS export
    metadata = {
        'gap_angles': gap_angles,
        'gap_width_deg': gap_width_deg,
        'usable_arc_deg': usable_arc,
        'arc_start_deg': (gap_angles[1] + gap_width_deg / 2.0) % 360.0,
        'arc_end_deg': (gap_angles[0] - gap_width_deg / 2.0) % 360.0,
        'r_inner': r_inner,
        'r_outer': r_outer,
        'n_inner': n_inner,
        'n_outer': n_outer,
    }

    return all_positions, metadata


def build_distance_matrix(positions):
    """Pre-compute 26×26 Euclidean distance matrix."""
    n = len(positions)
    dist = np.zeros((n, n))
    for i in range(n):
        for j in range(i + 1, n):
            dx = positions[i][0] - positions[j][0]
            dy = positions[i][1] - positions[j][1]
            d = math.sqrt(dx * dx + dy * dy)
            dist[i][j] = d
            dist[j][i] = d
    return dist


def build_bigram_matrix():
    """
    Build a 26×26 numpy array of bigram frequencies.
    Index by letter ordinal (A=0, B=1, ..., Z=25).
    """
    freq = np.zeros((26, 26))
    for i, a in enumerate(LETTERS):
        for j, b in enumerate(LETTERS):
            freq[i][j] = BIGRAM_FREQ.get(a + b, 0.0)
    return freq


def build_reach_cost(positions):
    """
    Compute ergonomic reach cost for each slot position.
    Higher cost = harder to reach with right thumb.
    Bottom-right (in screen coords) is hardest.
    In math coords: reach_cost = x - y (large x, negative y = bottom-right in iOS).
    Normalized to [0, 1] range.
    """
    raw = [pos[0] - pos[1] for pos in positions]
    min_r, max_r = min(raw), max(raw)
    span = max_r - min_r if max_r != min_r else 1.0
    return [(r - min_r) / span for r in raw]


def build_center_distance(positions):
    """Distance from center for each slot. Inner ring ≈ 1.0, outer ring ≈ 2.2."""
    return [math.sqrt(p[0]**2 + p[1]**2) for p in positions]


def build_letter_freq_array():
    """Build array of letter frequencies indexed by ordinal (A=0..Z=25)."""
    return [LETTER_FREQ.get(LETTERS[i], 0.0) for i in range(26)]


# Weights for energy terms:
# - CENTER: frequent letters should be on inner ring (close to center)
# - ERGO: within a ring, frequent letters should be in easy positions (top-left)
# - Bigram separation is implicitly weight=1
CENTER_WEIGHT = 8.0
ERGO_WEIGHT = 2.0


def compute_energy(state, dist_matrix, bigram_matrix,
                   reach_cost, center_dist, letter_freq_arr):
    """
    Energy for swipe-typing optimization:
      -1 * sum(bigram_freq * dist)       → maximize separation of common pairs
      + CENTER * sum(freq * center_dist)  → frequent letters close to center
      + ERGO * sum(freq * reach_cost)     → frequent letters in easy-to-reach spots
    """
    letter_to_pos = [0] * 26
    for pos_idx, letter in enumerate(state):
        letter_to_pos[ord(letter) - ord('A')] = pos_idx

    bigram_energy = 0.0
    for i in range(26):
        for j in range(26):
            f = bigram_matrix[i][j]
            if f > 0:
                bigram_energy += f * dist_matrix[letter_to_pos[i]][letter_to_pos[j]]

    center_energy = 0.0
    ergo_energy = 0.0
    for i in range(26):
        pos = letter_to_pos[i]
        center_energy += letter_freq_arr[i] * center_dist[pos]
        ergo_energy += letter_freq_arr[i] * reach_cost[pos]

    return -bigram_energy + CENTER_WEIGHT * center_energy + ERGO_WEIGHT * ergo_energy


def compute_energy_delta(state, dist_matrix, bigram_matrix, idx1, idx2,
                         letter_to_pos, reach_cost, center_dist, letter_freq_arr):
    """
    Compute the change in energy from swapping state[idx1] and state[idx2].
    O(26) instead of O(676).
    """
    li1 = ord(state[idx1]) - ord('A')
    li2 = ord(state[idx2]) - ord('A')

    bigram_delta = 0.0
    for k in range(26):
        if k == li1 or k == li2:
            continue
        pos_k = letter_to_pos[k]

        f1k = bigram_matrix[li1][k]
        fk1 = bigram_matrix[k][li1]
        if f1k > 0 or fk1 > 0:
            bigram_delta += (f1k + fk1) * (dist_matrix[idx2][pos_k] - dist_matrix[idx1][pos_k])

        f2k = bigram_matrix[li2][k]
        fk2 = bigram_matrix[k][li2]
        if f2k > 0 or fk2 > 0:
            bigram_delta += (f2k + fk2) * (dist_matrix[idx1][pos_k] - dist_matrix[idx2][pos_k])

    center_delta = (
        letter_freq_arr[li1] * (center_dist[idx2] - center_dist[idx1]) +
        letter_freq_arr[li2] * (center_dist[idx1] - center_dist[idx2])
    )

    ergo_delta = (
        letter_freq_arr[li1] * (reach_cost[idx2] - reach_cost[idx1]) +
        letter_freq_arr[li2] * (reach_cost[idx1] - reach_cost[idx2])
    )

    return -bigram_delta + CENTER_WEIGHT * center_delta + ERGO_WEIGHT * ergo_delta


def anneal(positions, n_iterations=500_000, t_start=None, cooling=0.9995, seed=None):
    """
    Run simulated annealing to find optimal letter arrangement.
    Returns (best_state, best_energy, energy_history).
    """
    if seed is not None:
        random.seed(seed)

    dist_matrix = build_distance_matrix(positions)
    bigram_matrix = build_bigram_matrix()
    reach_cost = build_reach_cost(positions)
    center_dist = build_center_distance(positions)
    letter_freq_arr = build_letter_freq_array()

    # Random initial state
    state = LETTERS[:]
    random.shuffle(state)

    current_energy = compute_energy(state, dist_matrix, bigram_matrix,
                                    reach_cost, center_dist, letter_freq_arr)

    # Maintain letter_to_pos: letter_to_pos[letter_index] = position_index
    letter_to_pos = [0] * 26
    for pos_idx, letter in enumerate(state):
        letter_to_pos[ord(letter) - ord('A')] = pos_idx

    # Calibrate starting temperature
    if t_start is None:
        deltas = []
        for _ in range(1000):
            i, j = random.sample(range(26), 2)
            d = compute_energy_delta(state, dist_matrix, bigram_matrix, i, j,
                                     letter_to_pos, reach_cost, center_dist, letter_freq_arr)
            deltas.append(abs(d))
        median_delta = sorted(deltas)[500]
        t_start = -median_delta / math.log(0.8)

    best_state = state[:]
    best_energy = current_energy
    T = t_start

    history_interval = max(1, n_iterations // 200)
    energy_history = []

    for step in range(n_iterations):
        idx1, idx2 = random.sample(range(26), 2)

        delta = compute_energy_delta(state, dist_matrix, bigram_matrix, idx1, idx2,
                                     letter_to_pos, reach_cost, center_dist, letter_freq_arr)

        if delta < 0 or random.random() < math.exp(-delta / T):
            li1 = ord(state[idx1]) - ord('A')
            li2 = ord(state[idx2]) - ord('A')
            letter_to_pos[li1] = idx2
            letter_to_pos[li2] = idx1

            state[idx1], state[idx2] = state[idx2], state[idx1]
            current_energy += delta

            if current_energy < best_energy:
                best_energy = current_energy
                best_state = state[:]

        T *= cooling

        if step % history_interval == 0:
            energy_history.append((step, current_energy))

    return best_state, best_energy, energy_history
