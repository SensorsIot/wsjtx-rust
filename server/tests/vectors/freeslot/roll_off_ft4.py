"""Reference vector for TC-039-050 (a) (#66): the WSJT-X passband floor of the 2026-11-07 FT4
roll-off table and the Tx slot it implies, computed here independently of the Rust code.

The table (as the test writes it): per native bin k (k x 12000/4096 Hz) 30 dB flat to 2400 Hz,
falling linearly to 15 dB at 2700 Hz (5 dB per 100 Hz, a sharp knee; 15 dB above), AA3B 12 dB
above it at 2621..2711 Hz, each bin rounded to whole dB (half away from zero) as the detailed rows
are. Two runs: "flat" as is, and "station" with an undecoded station 18 dB above the table at
1500.5..1590.5 Hz (an FT4 signal on the current Tx, bins 513..542; its level and position chosen
so that every candidate deciding the choice lies at least 0.1 dB from a half dB, margin_db, and
so that the parent's rule, the rise over each slot's usual level, makes the same choice).

The floor (#66 Functionality 3, the WSJT-X FT8/FT4 decoder baseline): the bins 103..921
(300..2700 Hz), ten segments of 81 bins from bin 103, in each the bins at or below its 8th lowest
level (rank 0.1 x 81 + 0.5 rounded down), one fourth-order least-squares fit through all of them
(numpy.polynomial.Polynomial.fit), plus 0.65 dB.

The choice (#66 Functionality 4 and 6, operator 2026-11-08 "At or under floor = free"): FT4, the
current Tx 1500, the called station KC8ZPI at 513 Hz, Hold Tx off, four identical counted periods
and no decoded station in them. A slot at f covers the bins of [f, f + 90) Hz; its rise is its mean
level minus the mean floor over the same bins; its value is the rise clamped at 0 and rounded to
whole dB (half away from zero); candidates every 10 Hz in 300..2610 at least 50 Hz clear of
KC8ZPI's signal; the lowest value wins, a tie keeps 1500, else the nearer to it, then the lower.

Margins, the smallest distance of a value to a half dB, where rounding would turn:
- margin_db: over the candidates that decide the choice, those no farther from the current Tx
  than the chosen slot (the test requires at least 0.1 dB);
- margin_all_db: over every candidate's clamped value;
- margin_raw_db: over every candidate's rise before the clamp.
unclamped is the choice of the same rule without the clamp (the 2530 failure the clamp prevents).

Rewrite roll_off_ft4.json next to this script: python roll_off_ft4.py
"""
import json
import math
import pathlib
import platform

import numpy as np

BIN = 12000 / 4096
CURRENT, CALLED, WIDTH = 1500, 513, 90


def round_half_away(x):
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def roll_off(hz):
    return 30.0 if hz < 2400.0 else max(30.0 - 15.0 * (hz - 2400.0) / 300.0, 15.0)


def with_aa3b(hz):
    return roll_off(hz) + (12.0 if 2621.0 <= hz < 2711.0 else 0.0)


def with_station(hz):
    return with_aa3b(hz) + (18.0 if 1500.5 <= hz < 1590.5 else 0.0)


FIRST, LAST = math.ceil(300 / BIN), math.ceil(2700 / BIN) - 1
assert (FIRST, LAST) == (103, 921)
SEGMENT = (LAST - FIRST + 1) // 10
RANK = int(0.1 * SEGMENT + 0.5)
assert (SEGMENT, RANK) == (81, 8)


def passband_floor(levels):
    xs, ys = [], []
    for s in range(10):
        begin = FIRST + s * SEGMENT
        segment = levels[begin:begin + SEGMENT]
        cutoff = sorted(segment)[RANK - 1]
        for i, y in enumerate(segment):
            if y <= cutoff:
                xs.append(begin + i)
                ys.append(float(y))
    fit = np.polynomial.Polynomial.fit(xs, ys, 4)
    return [float(fit(k)) + 0.65 for k in range(FIRST, LAST + 1)]


def half_distance(v):
    return abs(abs(v - math.floor(v)) - 0.5)


def choose(values):
    least = min(values.values())
    quietest = [f for f in values if values[f] == least]
    hz = CURRENT if CURRENT in quietest else min(quietest, key=lambda f: (abs(f - CURRENT), f))
    return hz, least


def run(name, level):
    levels = [round_half_away(level(k * BIN)) for k in range(1024)]
    floor = passband_floor(levels)

    def rise(f):
        bins = range(math.ceil(f / BIN), math.ceil((f + WIDTH) / BIN))
        mean = sum(levels[k] for k in bins) / len(bins)
        under = sum(floor[k - FIRST] for k in bins) / len(bins)
        return mean - under

    candidates = [f for f in range(300, 2611, 10)
                  if f + WIDTH + 50 <= CALLED or f >= CALLED + WIDTH + 50]
    rises = {f: rise(f) for f in candidates}
    clamped = {f: max(0.0, r) for f, r in rises.items()}
    hz, value = choose({f: round_half_away(v) for f, v in clamped.items()})
    deciding = [f for f in candidates if abs(f - CURRENT) <= abs(hz - CURRENT)]
    raw_hz, raw_value = choose({f: round_half_away(r) for f, r in rises.items()})
    return {
        "name": name,
        "levels_db": levels,
        "floor_db": floor,
        "choice": {
            "mode": "ft4", "current_hz": CURRENT, "called_hz": CALLED, "hz": hz, "power_db": value,
            "margin_db": min(half_distance(clamped[f]) for f in deciding),
            "margin_all_db": min(half_distance(v) for v in clamped.values()),
            "margin_raw_db": min(half_distance(r) for r in rises.values()),
            "unclamped": {"hz": raw_hz, "power_db": raw_value},
        },
    }


out = {
    "case": "tc_039_050_a_ft4_roll_off",
    "source": (f"server/tests/vectors/freeslot/roll_off_ft4.py, numpy {np.__version__} "
               f"numpy.polynomial.Polynomial.fit (least squares, degree 4), "
               f"Python {platform.python_version()}; floor within tolerance_db, choice exact"),
    "tolerance_db": 1e-6,
    "first_bin": FIRST,
    "runs": [run("flat", with_aa3b), run("station", with_station)],
}
path = pathlib.Path(__file__).with_name("roll_off_ft4.json")
path.write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
for r in out["runs"]:
    c = r["choice"]
    print(f"{r['name']}: hz {c['hz']}, power_db {c['power_db']}, margin_db {c['margin_db']:.4f}, "
          f"margin_all_db {c['margin_all_db']:.4f}, margin_raw_db {c['margin_raw_db']:.4f}, "
          f"unclamped {c['unclamped']}")
