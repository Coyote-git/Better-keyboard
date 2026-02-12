#!/usr/bin/env python3
"""
CLI entry point for the circular keyboard layout optimizer.
Runs simulated annealing multiple times and keeps the best result.
"""

import argparse
import json
import math
import time

from optimizer import (compute_positions, anneal, compute_energy,
                       build_distance_matrix, build_bigram_matrix,
                       build_reach_cost, build_center_distance,
                       build_letter_freq_array, LETTERS)
from bigrams import BIGRAM_FREQ, LETTER_FREQ
from visualize import plot_layout


def main():
    parser = argparse.ArgumentParser(description='Circular keyboard layout optimizer')
    parser.add_argument('--runs', type=int, default=5, help='Number of annealing runs (default: 5)')
    parser.add_argument('--iterations', type=int, default=500_000, help='Iterations per run (default: 500000)')
    parser.add_argument('--inner', type=int, default=8, help='Slots on inner ring (default: 8)')
    parser.add_argument('--outer', type=int, default=18, help='Slots on outer ring (default: 18)')
    parser.add_argument('--r-inner', type=float, default=1.0, help='Inner ring radius (default: 1.0)')
    parser.add_argument('--r-outer', type=float, default=2.2, help='Outer ring radius (default: 2.2)')
    parser.add_argument('--cooling', type=float, default=0.9995, help='Cooling factor (default: 0.9995)')
    parser.add_argument('--output', type=str, default='layout.png', help='Output image filename')
    parser.add_argument('--no-gaps', action='store_true', help='Use full 360° rings (no gaps)')
    args = parser.parse_args()

    assert args.inner + args.outer == 26, f'Inner + outer must equal 26, got {args.inner + args.outer}'

    if args.no_gaps:
        positions, metadata = compute_positions(
            args.inner, args.outer, args.r_inner, args.r_outer,
            gap_angles=[], gap_width_deg=0.0,
        )
    else:
        positions, metadata = compute_positions(
            args.inner, args.outer, args.r_inner, args.r_outer,
        )

    print(f'Circular Keyboard Layout Optimizer')
    print(f'  Inner ring: {args.inner} slots at radius {args.r_inner}')
    print(f'  Outer ring: {args.outer} slots at radius {args.r_outer}')
    if not args.no_gaps:
        print(f'  Gaps: {metadata["gap_angles"]} ({metadata["gap_width_deg"]}° each)')
        print(f'  Usable arc: {metadata["usable_arc_deg"]}°')
    print(f'  Iterations per run: {args.iterations:,}')
    print(f'  Number of runs: {args.runs}')
    print()

    # Compute random baseline energy for comparison
    import random
    dist_matrix = build_distance_matrix(positions)
    bigram_matrix = build_bigram_matrix()
    reach_cost = build_reach_cost(positions)
    center_dist = build_center_distance(positions)
    letter_freq_arr = build_letter_freq_array()
    random_energies = []
    for _ in range(100):
        rand_state = LETTERS[:]
        random.shuffle(rand_state)
        random_energies.append(compute_energy(rand_state, dist_matrix, bigram_matrix,
                                              reach_cost, center_dist, letter_freq_arr))
    avg_random_energy = sum(random_energies) / len(random_energies)

    best_state = None
    best_energy = float('inf')
    best_history = None

    total_start = time.time()

    for run in range(args.runs):
        print(f'Run {run + 1}/{args.runs}...', end=' ', flush=True)
        start = time.time()
        state, energy, history = anneal(
            positions,
            n_iterations=args.iterations,
            cooling=args.cooling,
        )
        elapsed = time.time() - start
        print(f'energy: {energy:.6f}  ({elapsed:.1f}s)')

        if energy < best_energy:
            best_energy = energy
            best_state = state
            best_history = history

    total_elapsed = time.time() - total_start
    print()
    print(f'Total time: {total_elapsed:.1f}s')
    print()

    # Results
    print('=' * 50)
    print('BEST LAYOUT')
    print('=' * 50)
    print()
    print(f'Energy: {best_energy:.6f}')
    print(f'Random baseline: {avg_random_energy:.6f}')
    improvement = (1 - best_energy / avg_random_energy) * 100
    print(f'Improvement over random: {improvement:.1f}%')
    print()

    inner_letters = best_state[:args.inner]
    outer_letters = best_state[args.inner:]

    print(f'Inner ring ({args.inner} slots): {" ".join(inner_letters)}')
    print(f'Outer ring ({args.outer} slots): {" ".join(outer_letters)}')
    print()

    # Show which of the top frequent letters landed on inner ring
    sorted_by_freq = sorted(LETTER_FREQ.items(), key=lambda x: x[1], reverse=True)
    top_8 = [l for l, _ in sorted_by_freq[:8]]
    inner_set = set(inner_letters)
    top_on_inner = [l for l in top_8 if l in inner_set]
    print(f'Top 8 most frequent letters: {" ".join(top_8)}')
    print(f'Of those, on inner ring: {" ".join(top_on_inner)} ({len(top_on_inner)}/8)')
    print()

    # Check top bigrams
    print('Top 10 bigrams — distance check:')
    sorted_bigrams = sorted(BIGRAM_FREQ.items(), key=lambda x: x[1], reverse=True)[:10]
    letter_to_pos = {}
    for i, letter in enumerate(best_state):
        letter_to_pos[letter] = i
    for pair, freq in sorted_bigrams:
        a, b = pair[0], pair[1]
        pos_a = letter_to_pos[a]
        pos_b = letter_to_pos[b]
        dist = dist_matrix[pos_a][pos_b]
        ring_a = 'inner' if pos_a < args.inner else 'outer'
        ring_b = 'inner' if pos_b < args.inner else 'outer'
        print(f'  {pair}: dist={dist:.2f}  ({a}@{ring_a}, {b}@{ring_b})')
    print()

    # Export layout with position data for iOS
    print('=' * 50)
    print('LAYOUT FOR iOS (copy-paste)')
    print('=' * 50)
    print()
    print(f'inner_ring = {inner_letters}')
    print(f'outer_ring = {outer_letters}')
    print()
    print(f'# Full state (position order):')
    print(f'layout = {best_state}')
    print()

    # Export slot data as JSON for iOS consumption
    slots = []
    for i, letter in enumerate(best_state):
        ring = 'inner' if i < args.inner else 'outer'
        x, y = positions[i]
        angle_rad = math.atan2(y, x)
        angle_deg = math.degrees(angle_rad) % 360.0
        slots.append({
            'letter': letter,
            'ring': ring,
            'index': i,
            'angle_deg': round(angle_deg, 2),
            'x': round(x, 4),
            'y': round(y, 4),
        })
    layout_data = {
        'slots': slots,
        'metadata': {
            'energy': best_energy,
            'r_inner': metadata['r_inner'],
            'r_outer': metadata['r_outer'],
            'n_inner': metadata['n_inner'],
            'n_outer': metadata['n_outer'],
            'gap_angles': metadata['gap_angles'],
            'gap_width_deg': metadata['gap_width_deg'],
            'usable_arc_deg': metadata['usable_arc_deg'],
            'arc_start_deg': metadata['arc_start_deg'],
            'arc_end_deg': metadata['arc_end_deg'],
        }
    }
    json_path = args.output.replace('.png', '_data.json')
    with open(json_path, 'w') as f:
        json.dump(layout_data, f, indent=2)
    print(f'Layout data exported to {json_path}')
    print()

    # Energy history
    if best_history:
        first_e = best_history[0][1]
        last_e = best_history[-1][1]
        print(f'Energy progression: {first_e:.6f} -> {last_e:.6f}')

    # Visualize
    plot_layout(best_state, positions, metadata, BIGRAM_FREQ, best_energy, filename=args.output)


if __name__ == '__main__':
    main()
