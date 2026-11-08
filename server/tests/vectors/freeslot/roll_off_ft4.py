"""Reference vector for TC-039-050 (a) (#66): the WSJT-X passband floor of the 2026-11-07 FT4
roll-off table and the Tx slot it implies, computed here independently of the Rust code.

The table (as the test writes it): per native bin k (k x 12000/4096 Hz) 30 dB, falling linearly
from 2400 Hz to 15 dB at 2700 Hz (15 dB above), AA3B 12 dB above it at 2621..2711 Hz, each bin
rounded to whole dB (half away from zero) as the detailed rows are.

The floor (#66 Functionality 3, the WSJT-X FT8/FT4 decoder baseline): the bins 103..921
(300..2700 Hz), ten segments of 81 bins from bin 103, in each the bins at or below its 8th lowest
level (rank 0.1 x 81 + 0.5 rounded down), one fourth-order least-squares fit through all of them
(numpy.polynomial.Polynomial.fit), plus 0.65 dB.

The choice (#66 Functionality 4 and 6): FT4, the current Tx 1500, the called station KC8ZPI at
513 Hz, Hold Tx off, four identical counted periods and no decoded station in them. A slot at f
covers the bins of [f, f + 90) Hz; its value is its mean level minus the mean floor over the same
bins, rounded to whole dB (half away from zero); candidates every 10 Hz in 300..2610 at least
50 Hz clear of KC8ZPI's signal; the lowest value wins, a tie keeps 1500, else the nearer to it,
then the lower. margin_db is the smallest distance of any candidate's value to a half dB, where
rounding would turn.

Rewrite roll_off_ft4.json next to this script: python roll_off_ft4.py
"""
import json
import math
import pathlib
import platform

import numpy as np

BIN = 12000 / 4096


def round_half_away(x):
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def roll_off(hz):
    return 30.0 if hz < 2400.0 else max(30.0 - 15.0 * (hz - 2400.0) / 300.0, 15.0)


def with_aa3b(hz):
    return roll_off(hz) + (12.0 if 2621.0 <= hz < 2711.0 else 0.0)


levels = [round_half_away(with_aa3b(k * BIN)) for k in range(1024)]
first, last = math.ceil(300 / BIN), math.ceil(2700 / BIN) - 1
assert (first, last) == (103, 921)
width = (last - first + 1) // 10
rank = int(0.1 * width + 0.5)
assert (width, rank) == (81, 8)
xs, ys = [], []
for s in range(10):
    begin = first + s * width
    segment = levels[begin:begin + width]
    cutoff = sorted(segment)[rank - 1]
    for i, y in enumerate(segment):
        if y <= cutoff:
            xs.append(begin + i)
            ys.append(float(y))
fit = np.polynomial.Polynomial.fit(xs, ys, 4)
floor = [float(fit(k)) + 0.65 for k in range(first, last + 1)]

current, called, w = 1500, 513, 90


def value(f):
    bins = range(math.ceil(f / BIN), math.ceil((f + w) / BIN))
    level = sum(levels[k] for k in bins) / len(bins)
    under = sum(floor[k - first] for k in bins) / len(bins)
    return level - under


candidates = [f for f in range(300, 2611, 10) if f + w + 50 <= called or f >= called + w + 50]
values = {f: value(f) for f in candidates}
whole = {f: round_half_away(v) for f, v in values.items()}
least = min(whole.values())
quietest = [f for f in candidates if whole[f] == least]
hz = current if current in quietest else min(quietest, key=lambda f: (abs(f - current), f))
margin = min(abs(abs(v - math.floor(v)) - 0.5) for v in values.values())

out = {
    "case": "tc_039_050_a_ft4_roll_off",
    "source": (f"server/tests/vectors/freeslot/roll_off_ft4.py, numpy {np.__version__} "
               f"numpy.polynomial.Polynomial.fit (least squares, degree 4), "
               f"Python {platform.python_version()}; floor within tolerance_db, choice exact"),
    "tolerance_db": 1e-6,
    "levels_db": levels,
    "first_bin": first,
    "floor_db": floor,
    "choice": {"mode": "ft4", "current_hz": current, "called_hz": called, "hz": hz,
               "power_db": least, "margin_db": margin},
}
path = pathlib.Path(__file__).with_name("roll_off_ft4.json")
path.write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
print(f"{path}: hz {hz}, power_db {least}, margin_db {margin:.4f}")
