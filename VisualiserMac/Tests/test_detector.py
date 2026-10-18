#!/usr/bin/env python3
"""Offline harness for GenreDetector scoring.

Mirrors the ramp/bell scoring in Band/GenreDetector.swift exactly. Kept in
Python so the arithmetic is easy to eyeball and tweak; if the Swift rules
change, this must be updated to match.
"""

def ramp(x, lo, hi):
    if hi == lo:
        return 1.0 if x >= hi else 0.0
    return min(1.0, max(0.0, (x - lo) / (hi - lo)))

def bell(x, ideal, width):
    return max(0.0, 1.0 - abs(x - ideal) / max(0.0001, width))

GENRES = ["classical","electronic","rock","pop","hiphop","jazz","blues","country","rnb","ambient"]

def score(bpm, bass, mid, treble, centroid, onsets, rng, vocal):
    bpmF = float(bpm)
    has_beat = bpm >= 40
    s = {}

    s["classical"] = (ramp(bpmF,110,45)*0.30 + ramp(rng,0.09,0.22)*0.30
                      + ramp(centroid,0.38,0.62)*0.22 + (1-ramp(onsets,0.05,0.35))*0.18)
    s["electronic"] = (bell(bpmF,128,26)*0.28 + ramp(bass,0.22,0.50)*0.30
                      + ramp(onsets,0.35,0.85)*0.22 + (1-ramp(rng,0.06,0.14))*0.20)
    s["rock"] = (bell(bpmF,128,34)*0.24 + ramp(mid,0.12,0.34)*0.24
                 + ramp(onsets,0.28,0.70)*0.22 + ramp(bass,0.10,0.30)*0.16
                 # Rock leaves headroom; a brickwalled mix shouldn't score full marks.
                 + ramp(rng,0.08,0.20)*0.14)
    s["pop"] = (bell(bpmF,118,24)*0.26 + ramp(vocal,0.12,0.32)*0.30
                + ramp(rng,0.07,0.17)*0.18 + bell(mid,0.26,0.18)*0.14
                + bell(bass,0.26,0.16)*0.12)
    s["hiphop"] = (bell(bpmF,88,22)*0.26 + ramp(bass,0.32,0.60)*0.44
                   + ramp(onsets,0.20,0.55)*0.30)
    s["rnb"] = (bell(bpmF,86,20)*0.26 + ramp(vocal,0.15,0.38)*0.38
                + bell(bass,0.24,0.13)*0.22 + ramp(rng,0.07,0.16)*0.14)
    s["jazz"] = (bell(bpmF,135,40)*0.26 + bell(mid,0.32,0.16)*0.30
                 + bell(onsets,0.32,0.20)*0.24 + ramp(vocal,0.06,0.22)*0.20)
    s["blues"] = (bell(bpmF,78,26)*0.26 + (1-ramp(onsets,0.05,0.30))*0.26
                  + (1-ramp(treble,0.04,0.14))*0.28 + ramp(mid,0.14,0.32)*0.20)
    s["country"] = (bell(bpmF,104,24)*0.24 + ramp(treble,0.10,0.24)*0.30
                    + ramp(vocal,0.10,0.30)*0.26 + ramp(onsets,0.18,0.48)*0.20)
    s["ambient"] = ((1-ramp(onsets,0.02,0.22))*0.55 + (1-ramp(rng,0.04,0.22))*0.25
                    + (0.20 if bpm < 60 else 0.0))

    if not has_beat:
        for g in GENRES:
            if g != "ambient":
                s[g] = 0.0

    ranked = sorted(s.items(), key=lambda kv: -kv[1])
    top, runner = ranked[0], (ranked[1][1] if len(ranked) > 1 else 0.0)
    margin = max(0.0, top[1] - runner)
    return top[0], min(1.0, margin/0.18), s, ranked[:2]

TESTS = [
    ("Classical  72bpm wide bright sparse", (72, 0.20,0.35,0.40,0.62,0.12,0.22,0.25), "classical"),
    ("Electronic 128bpm bass dense flat",    (128,0.55,0.30,0.35,0.55,0.70,0.06,0.05), "electronic"),
    ("Rock       128bpm mid driving",       (128,0.30,0.35,0.30,0.50,0.60,0.14,0.10), "rock"),
    ("Pop        118bpm vocal balanced",    (118,0.26,0.26,0.26,0.50,0.40,0.14,0.45), "pop"),
    ("Hip-Hop    88bpm 808",                (88, 0.55,0.25,0.15,0.35,0.45,0.12,0.20), "hiphop"),
    ("Jazz       135bpm brushed",           (135,0.20,0.32,0.25,0.50,0.32,0.12,0.20), "jazz"),
    ("Blues      75bpm dark sparse",        (75, 0.25,0.32,0.06,0.35,0.18,0.16,0.30), "blues"),
    ("Country    104bpm bright strum",      (104,0.22,0.30,0.28,0.55,0.45,0.13,0.35), "country"),
    ("R&B        86bpm smooth vocal",       (86, 0.24,0.28,0.18,0.42,0.35,0.13,0.42), "rnb"),
    ("Ambient    no beat drone",            (0,  0.15,0.18,0.12,0.40,0.03,0.09,0.0),  "ambient"),
    ("Ballad     no beat vocal dark",       (0,  0.20,0.30,0.15,0.40,0.15,0.18,0.30), "ambient"),
    ("Slow dark heavy-bass (blues-ish)",   (70, 0.50,0.30,0.06,0.35,0.15,0.14,0.20), "blues"),
    ("Slow bright strum (country-ish)",     (95, 0.22,0.30,0.26,0.55,0.45,0.13,0.35), "country"),
    ("Mid vocal heavy-ish (rnb-ish)",       (92, 0.30,0.28,0.18,0.42,0.35,0.13,0.45), "rnb"),
    ("Very heavy bass 90bpm (hiphop)",      (90, 0.62,0.25,0.14,0.33,0.45,0.12,0.15), "hiphop"),
]

passed = failed = 0
for name, args, expect in TESTS:
    got, conf, _, top2 = score(*args)
    ok = got == expect
    passed += ok
    failed += (not ok)
    t2 = "  ".join(f"{k}={v:.2f}" for k, v in top2)
    print(f"{'PASS' if ok else 'FAIL'}  {name}")
    print(f"      expected={expect:10s} got={got:10s} conf={conf:.2f}   top2: {t2}")

print(f"\n{passed} passed, {failed} failed")