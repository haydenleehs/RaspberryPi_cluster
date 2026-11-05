#!/usr/bin/env python3
"""Plot wall times + Amdahl's law curve from pi_montecarlo.py .out files.

Run on picluster-login (needs matplotlib: sudo apt install -y python3-matplotlib):
    python3 plot_speedup.py [/clusterfs/pi]

Writes speedup.png next to the .out files.
"""
import glob
import os
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

directory = sys.argv[1] if len(sys.argv) > 1 else "/clusterfs/pi"


def latest_time(prefix):
    files = sorted(glob.glob(os.path.join(directory, f"{prefix}-*.out")),
                    key=os.path.getmtime, reverse=True)
    if not files:
        return None
    text = open(files[0]).read()
    m = re.search(r"computed in ([\d.]+) s", text)
    return float(m.group(1)) if m else None


runs = [("1 rank\n1 node", "pi-1rank", 1),
        ("4 ranks\n1 node", "pi-4rank", 4),
        ("16 ranks\n4 nodes", "pi-16rank", 16)]

labels, times, ranks = [], [], []
for label, prefix, n in runs:
    t = latest_time(prefix)
    if t is not None:
        labels.append(label)
        times.append(t)
        ranks.append(n)

if not times:
    sys.exit(f"No .out files found in {directory}")

t1 = times[0]
s = 5.0  # fixed serial section, seconds (matches pi_montecarlo.py SERIAL_WORK)
f = s / t1  # measured serial fraction

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.5))

# --- bar chart: serial (red) stacked under parallel (teal) ---
serial_part = [min(s, t) for t in times]
parallel_part = [max(t - s, 0) for t in times]
x = np.arange(len(labels))
ax1.bar(x, parallel_part, bottom=serial_part, color="#2a6f7a", label="parallel work")
ax1.bar(x, serial_part, color="#e2645a", label="fixed setup")
for i, t in enumerate(times):
    ax1.text(i, t + max(times) * 0.02, f"{t:.1f}s", ha="center", fontweight="bold")
ax1.set_xticks(x, labels)
ax1.set_ylabel("wall time (s)")
ax1.set_title("Wall time by run")
ax1.legend(frameon=False, loc="upper right")
ax1.spines[["top", "right"]].set_visible(False)

# --- Amdahl's law curve ---
n_range = np.linspace(1, 16, 200)
amdahl = 1 / (f + (1 - f) / n_range)
ax2.plot(n_range, n_range, "--", color="gray", label="ideal (linear)")
ax2.plot(n_range, amdahl, color="#2a6f7a", lw=2.5, label=f"Amdahl (f={f*100:.0f}% serial)")
measured_speedup = [t1 / t for t in times]
ax2.scatter(ranks, measured_speedup, color="#f0a94e", zorder=5, s=60, label="measured")
for n, sp in zip(ranks, measured_speedup):
    ax2.annotate(f"{sp:.1f}x", (n, sp), textcoords="offset points", xytext=(0, 8), ha="center")
ax2.set_xlabel("cores")
ax2.set_ylabel("speedup")
ax2.set_title("Amdahl's law")
ax2.legend(frameon=False, loc="upper left")
ax2.spines[["top", "right"]].set_visible(False)

fig.suptitle("Raspberry Pi cluster — \u03c0 estimation speedup", fontweight="bold")
fig.tight_layout()
out = os.path.join(directory, "speedup.png")
fig.savefig(out, dpi=150)
print(f"wrote {out}")
