#!/bin/bash
# Fails if the landing page's mode cards (data-mode="…" in site/index.html)
# don't match the app's visualiser modes, so a new mode can't ship without
# being documented on the site.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import re, sys
root = sys.argv[1]
src = open(f"{root}/VisualiserMac/Sources/VisualiserMac/AppState.swift").read()
enum = src[src.index("enum VisualizerMode"):]
enum = enum[:enum.index("var displayName")]
app = set(re.findall(r"case\s+([a-zA-Z]+(?:\s*,\s*[a-zA-Z]+)*)", enum))
app = {c.strip() for group in app for c in group.split(",")} - {"autoScan"}
site = set(re.findall(r'data-mode="([a-zA-Z]+)"', open(f"{root}/site/index.html").read()))
missing, extra = sorted(app - site), sorted(site - app)
if missing or extra:
    if missing: print("Modes missing from site/index.html:", ", ".join(missing))
    if extra: print("site/index.html lists modes the app doesn't have:", ", ".join(extra))
    sys.exit(1)
print(f"site/index.html covers all {len(app)} modes")
PY
