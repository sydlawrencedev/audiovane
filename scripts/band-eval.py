#!/usr/bin/env python3
"""Score The Band's genre and line-up detection against labelled videos.

Plays each video in VisualiserMac/Tests/band-fixtures.yaml in its own Google
Chrome tab, lets Vibresia (in The Band, auto genre on) listen through system
audio, and compares what it decided with the labels:

  * genre: the genre the detector settled on most over the listening window
  * band:  who was on stage at the end of the window

Before running: Vibresia must already have system audio permission (start it
once and click Share System Audio), Chrome must be installed, and nothing else
should be playing. Ads at the start of a video skew the result; YouTube
Premium or a later `start` helps.

Usage:
  scripts/band-eval.py                      # every fixture
  scripts/band-eval.py --only rock          # fixtures whose genre/note/url match
  scripts/band-eval.py --check              # just validate the fixtures file
  scripts/band-eval.py --seconds 60 --settle 20
"""
import argparse
import collections
import datetime
import json
import os
import re
import subprocess
import sys
import time

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAC = os.path.join(ROOT, "VisualiserMac")
FIXTURES = os.path.join(MAC, "Tests", "band-fixtures.yaml")
RESULTS = os.path.join(MAC, "Tests", "eval-results")
APP = os.path.join(MAC, "build", "Vibresia.app")
BUNDLE_ID = "com.minithlabs.visualiser"

GENRES = ["classical", "electronic", "rock", "pop", "hip-hop", "jazz", "blues", "country", "r&b", "ambient"]
MEMBERS = ["drums", "bass", "guitar", "keys", "female_singer", "male_singer"]


def load_fixtures(path):
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    fixtures = data.get("fixtures") or []
    problems = []
    for i, fx in enumerate(fixtures, 1):
        where = f"fixture {i} ({fx.get('note') or fx.get('url', '?')})"
        if not re.match(r"https?://(www\.)?(youtube\.com/watch\?|youtu\.be/|music\.youtube\.com/watch\?)", str(fx.get("url", ""))):
            problems.append(f"{where}: url isn't a YouTube link")
        if str(fx.get("genre", "")).lower() not in GENRES:
            problems.append(f"{where}: genre must be one of {', '.join(GENRES)}")
        band = fx.get("band") or []
        bad = [m for m in band if m not in MEMBERS]
        if bad or not band:
            problems.append(f"{where}: band must list some of {', '.join(MEMBERS)} (got {band})")
        if not isinstance(fx.get("start", 0), (int, float)):
            problems.append(f"{where}: start must be a number of seconds")
    return fixtures, problems


def video_url(url, start):
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}t={int(start)}s"


def osascript(script):
    out = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip())
    return out.stdout.strip()


def open_tab(url):
    """Open url in a new Chrome tab and return the tab's id."""
    return osascript(f'''
        tell application "Google Chrome"
            if (count of windows) = 0 then make new window
            set t to make new tab at end of tabs of front window with properties {{URL:"{url}"}}
            return id of t
        end tell''')


def close_tab(tab_id):
    osascript(f'''
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    if (id of t as text) is "{tab_id}" then close t
                end repeat
            end repeat
        end tell''')


def start_app(log_path, build):
    if build:
        print("Building Vibresia…")
        subprocess.run([os.path.join(MAC, "build-app.sh"), "debug"], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["osascript", "-e", f'tell application id "{BUNDLE_ID}" to quit'], capture_output=True)
    time.sleep(2)
    subprocess.run(["open", "-n", "-a", APP,
                    "--env", f"VIBRESIA_EVAL_LOG={log_path}",
                    "--env", "VIBRESIA_NO_UPDATE_CHECK=1",
                    "--args", "--mode", "band", "--system-audio", "--genre-auto"], check=True)
    time.sleep(8)


def read_log(path):
    lines = []
    if os.path.exists(path):
        with open(path) as f:
            for raw in f:
                try:
                    lines.append(json.loads(raw))
                except json.JSONDecodeError:
                    pass
    return lines


def score(fixture, lines, t0, settle, seconds):
    window = [l for l in lines if t0 + settle <= l["t"] <= t0 + seconds]
    expected_genre = fixture["genre"].lower()
    expected_band = set(fixture["band"])
    result = {
        "url": fixture["url"], "note": fixture.get("note", ""), "start": fixture.get("start", 0),
        "expected_genre": expected_genre, "expected_band": sorted(expected_band),
        "samples": len(window),
    }
    if not window:
        result.update(error="no log lines in the listening window (was Vibresia hearing system audio?)")
        return result
    votes = collections.Counter(l["detected"] for l in window)
    genre, n = votes.most_common(1)[0]
    final = window[-1]
    on_stage = set(final.get("on_stage", []))
    first_right = next((round(l["t"] - t0) for l in window if l["detected"] == expected_genre), None)
    result.update(
        genre=genre,
        genre_share=round(n / len(window), 2),
        genre_votes=dict(votes),
        genre_ok=genre == expected_genre,
        seconds_to_genre=first_right,
        confidence=round(sum(l["confidence"] for l in window) / len(window), 2),
        band=sorted(on_stage),
        missing=sorted(expected_band - on_stage),
        extra=sorted(on_stage - expected_band),
        band_ok=on_stage == expected_band,
        bpm=round(sum(l.get("bpm", 0) for l in window) / len(window)),
        features={k: round(sum(l["features"].get(k, 0) for l in window) / len(window), 3)
                  for k in window[-1].get("features", {})},
        scores={k: round(sum(l["scores"].get(k, 0) for l in window) / len(window), 3)
                for k in window[-1].get("scores", {})},
        classifier={k: round(sum(l["classifier"].get(k, 0) for l in window) / len(window), 2)
                    for k in window[-1].get("classifier", {})},
    )
    return result


def report(results):
    scored = [r for r in results if "error" not in r]
    print("\n" + "=" * 78)
    for r in results:
        label = r["note"] or r["url"]
        if "error" in r:
            print(f"✗ {label}: {r['error']}")
            continue
        g = "✓" if r["genre_ok"] else "✗"
        b = "✓" if r["band_ok"] else "✗"
        line = f"{g} genre {r['genre']:<10} (want {r['expected_genre']}, {int(r['genre_share'] * 100)}% of window, conf {r['confidence']})"
        print(f"{label}\n    {line}")
        detail = []
        if r["missing"]: detail.append("missing " + ", ".join(r["missing"]))
        if r["extra"]: detail.append("extra " + ", ".join(r["extra"]))
        print(f"    {b} band  {', '.join(r['band']) or '(empty)'}" + (f"  [{'; '.join(detail)}]" if detail else ""))
    if not scored:
        return
    print("=" * 78)
    gn = sum(r["genre_ok"] for r in scored)
    bn = sum(r["band_ok"] for r in scored)
    print(f"Genre {gn}/{len(scored)} correct · Band exactly right {bn}/{len(scored)}")
    confusions = collections.Counter(f"{r['expected_genre']} → {r['genre']}" for r in scored if not r["genre_ok"])
    if confusions:
        print("Genre confusions: " + ", ".join(f"{k} ×{v}" for k, v in confusions.most_common()))
    for m in MEMBERS:
        want = [r for r in scored if m in r["expected_band"]]
        got = [r for r in scored if m in r["band"]]
        hit = [r for r in want if m in r["band"]]
        if want or got:
            print(f"  {m:<14} heard in {len(hit)}/{len(want)} songs that have it; shown in {len(got) - len(hit)} that don't")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fixtures", default=FIXTURES)
    ap.add_argument("--only", help="run fixtures whose genre, note or url contains this text")
    ap.add_argument("--seconds", type=float, default=45, help="listening time per video (default 45)")
    ap.add_argument("--settle", type=float, default=15, help="ignore the first N seconds of each (default 15)")
    ap.add_argument("--gap", type=float, default=6, help="silence between videos (default 6)")
    ap.add_argument("--no-build", action="store_true", help="use the existing build/Vibresia.app")
    ap.add_argument("--check", action="store_true", help="only validate the fixtures file")
    args = ap.parse_args()

    fixtures, problems = load_fixtures(args.fixtures)
    if problems:
        print("Fixture problems:\n  " + "\n  ".join(problems))
        sys.exit(1)
    if args.only:
        q = args.only.lower()
        fixtures = [f for f in fixtures if q in (str(f.get("genre", "")) + str(f.get("note", "")) + f["url"]).lower()]
    if not fixtures:
        print("No fixtures to run. Add some to " + os.path.relpath(args.fixtures, ROOT))
        sys.exit(0 if args.check else 1)
    if args.check:
        print(f"{len(fixtures)} fixtures look fine.")
        return

    os.makedirs(RESULTS, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    log_path = os.path.join(RESULTS, f"{stamp}.log.jsonl")
    minutes = len(fixtures) * (args.seconds + args.gap) / 60
    print(f"Running {len(fixtures)} videos, about {minutes:.0f} min. Keep other audio off.")
    start_app(log_path, build=not args.no_build)

    timings = []
    for i, fx in enumerate(fixtures, 1):
        print(f"[{i}/{len(fixtures)}] {fx.get('note') or fx['url']}")
        t0 = time.time()
        tab = open_tab(video_url(fx["url"], fx.get("start", 0)))
        time.sleep(args.seconds)
        close_tab(tab)
        timings.append(t0)
        time.sleep(args.gap)

    lines = read_log(log_path)
    results = [score(fx, lines, t0, args.settle, args.seconds) for fx, t0 in zip(fixtures, timings)]
    report(results)
    out = os.path.join(RESULTS, f"{stamp}.json")
    with open(out, "w") as f:
        json.dump({"settings": vars(args), "results": results}, f, indent=2)
    print(f"\nDetails (features, per-genre scores, classifier): {os.path.relpath(out, ROOT)}")


if __name__ == "__main__":
    main()
