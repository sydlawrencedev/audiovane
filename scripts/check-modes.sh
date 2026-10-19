#!/bin/bash
# Fails if the landing page's mode cards (data-mode="…" in site/index.html)
# don't match the app's visualiser modes, or if the version in its structured
# data has drifted from VisualiserMac/VERSION. Both are things that go stale
# quietly, so both are checked at release time.
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
html = open(f"{root}/site/index.html").read()
site = set(re.findall(r'data-mode="([a-zA-Z]+)"', html))
missing, extra = sorted(app - site), sorted(site - app)
if missing or extra:
    if missing: print("Modes missing from site/index.html:", ", ".join(missing))
    if extra: print("site/index.html lists modes the app doesn't have:", ", ".join(extra))
    sys.exit(1)
print(f"site/index.html covers all {len(app)} modes")

# The structured data quotes the version. It's the one thing on the page that
# goes stale quietly, because nothing about it breaks when it does.
version = open(f"{root}/VisualiserMac/VERSION").read().strip()
schema = re.search(r'"softwareVersion":\s*"([^"]+)"', html)
if not schema:
    print("site/index.html has no \"softwareVersion\" in its JSON-LD.")
    sys.exit(1)
if schema.group(1) != version:
    print(f'JSON-LD softwareVersion is {schema.group(1)}, but VisualiserMac/VERSION says {version}.')
    sys.exit(1)
print(f"structured data matches VERSION {version}")
PY
