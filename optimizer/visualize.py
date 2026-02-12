"""
Visualization of the optimized circular keyboard layout.
Draws C-shaped arcs with gaps for backspace and reserved zones.
"""

import math
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.patches import Arc, Wedge
from bigrams import BIGRAM_FREQ, LETTER_FREQ


def plot_layout(state, positions, metadata, bigram_freqs=None, energy=None, filename='layout.png'):
    """
    Render the keyboard layout as a matplotlib figure.
    - Two concentric arc outlines (with gaps at specified angles)
    - Letters placed at their positions, sized by frequency
    - Gap zones shaded (backspace on left, reserved on right)
    - Lines between top 20 bigram pairs
    """
    if bigram_freqs is None:
        bigram_freqs = BIGRAM_FREQ

    r_inner = metadata['r_inner']
    r_outer = metadata['r_outer']
    gap_angles = metadata.get('gap_angles', [])
    gap_width = metadata.get('gap_width_deg', 0)

    fig, ax = plt.subplots(1, 1, figsize=(10, 10))
    ax.set_aspect('equal')
    ax.set_xlim(-3.2, 3.2)
    ax.set_ylim(-3.2, 3.2)
    ax.axis('off')

    if gap_angles and gap_width > 0:
        # Draw arcs with gaps
        arc_start = metadata['arc_start_deg']
        arc_end = metadata['arc_end_deg']
        # matplotlib Arc uses theta1, theta2 in degrees, CCW from right
        # Our arc goes from arc_start to arc_end CCW
        arc_extent = metadata['usable_arc_deg']

        for radius, label in [(r_inner, 'inner'), (r_outer, 'outer')]:
            arc = Arc((0, 0), 2 * radius, 2 * radius,
                      angle=0, theta1=arc_start, theta2=arc_start + arc_extent,
                      color='#888888', linewidth=1.5, linestyle='--')
            ax.add_patch(arc)

        # Draw gap zones
        gap_labels = ['backspace', 'reserved']
        gap_colors = ['#FFE0E0', '#E0E0E0']
        for i, (g_angle, g_start, g_end) in enumerate(
            [(ga, (ga - gap_width / 2) % 360, (ga + gap_width / 2) % 360)
             for ga in gap_angles]
        ):
            if i < len(gap_labels):
                # Draw a wedge from inner to outer radius
                wedge = Wedge((0, 0), r_outer + 0.15,
                              g_start if g_start < g_end else g_start,
                              g_end if g_start < g_end else g_end + 360,
                              width=r_outer - r_inner + 0.3,
                              facecolor=gap_colors[i % len(gap_colors)],
                              edgecolor='#AAAAAA', linewidth=0.8, alpha=0.5)
                ax.add_patch(wedge)
                # Label
                label_angle = math.radians(g_angle)
                label_r = (r_inner + r_outer) / 2
                lx = label_r * math.cos(label_angle)
                ly = label_r * math.sin(label_angle)
                ax.text(lx, ly, gap_labels[i], ha='center', va='center',
                        fontsize=8, color='#888888', style='italic')
    else:
        # Full circles (no gaps)
        inner_circle = plt.Circle((0, 0), r_inner, fill=False, color='#888888',
                                   linewidth=1.5, linestyle='--')
        outer_circle = plt.Circle((0, 0), r_outer, fill=False, color='#888888',
                                   linewidth=1.5, linestyle='--')
        ax.add_patch(inner_circle)
        ax.add_patch(outer_circle)

    # Center dot
    center = plt.Circle((0, 0), 0.15, color='#DDDDDD', ec='#999999', linewidth=1)
    ax.add_patch(center)
    ax.text(0, 0, '●', ha='center', va='center', fontsize=8, color='#999999')

    # Build letter→position mapping
    letter_pos = {}
    for i, letter in enumerate(state):
        letter_pos[letter] = positions[i]

    # Draw bigram lines for top 20 pairs
    sorted_bigrams = sorted(bigram_freqs.items(), key=lambda x: x[1], reverse=True)
    top_bigrams = [(pair, freq) for pair, freq in sorted_bigrams if freq > 0][:20]
    max_freq = top_bigrams[0][1] if top_bigrams else 1

    for pair, freq in top_bigrams:
        a, b = pair[0], pair[1]
        if a in letter_pos and b in letter_pos:
            x1, y1 = letter_pos[a]
            x2, y2 = letter_pos[b]
            alpha = 0.15 + 0.6 * (freq / max_freq)
            linewidth = 0.5 + 3.0 * (freq / max_freq)
            ax.plot([x1, x2], [y1, y2], color='#4A90D9', alpha=alpha,
                    linewidth=linewidth, zorder=1)

    # Draw letters
    max_letter_freq = max(LETTER_FREQ.values())
    for letter, (x, y) in letter_pos.items():
        freq = LETTER_FREQ.get(letter, 0.01)
        size = 12 + 16 * (freq / max_letter_freq)

        # Background circle for readability
        circle_r = 0.22 + 0.08 * (freq / max_letter_freq)
        bg = plt.Circle((x, y), circle_r, color='white', ec='#333333',
                         linewidth=1.2, zorder=2)
        ax.add_patch(bg)

        ax.text(x, y, letter, ha='center', va='center',
                fontsize=size, fontweight='bold', color='#222222', zorder=3)

    # Title
    title = 'Optimized Circular Keyboard Layout (C-Shape)'
    if energy is not None:
        title += f'  (energy: {energy:.6f})'
    ax.set_title(title, fontsize=14, pad=20)

    # Ring labels
    n_inner = metadata.get('n_inner', 8)
    n_outer = metadata.get('n_outer', 18)
    ax.text(0, -1.55, f'inner ring ({n_inner})', ha='center', va='center',
            fontsize=9, color='#888888')
    ax.text(0, -2.75, f'outer ring ({n_outer})', ha='center', va='center',
            fontsize=9, color='#888888')

    plt.tight_layout()
    plt.savefig(filename, dpi=150, bbox_inches='tight')
    plt.close()
    print(f'Layout saved to {filename}')
