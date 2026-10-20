#!/bin/bash
# Fails if the landing page's vibscape cards (data-vibscape="…" in site/index.html)
# don't match the app's vibscapes, or if the version in its structured
# data has drifted from VisualiserMac/VERSION. Both are things that go stale
# quietly, so both are checked at release time.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import re, sys
root = sys.argv[1]
src = open(f"{root}/VisualiserMac/Sources/VisualiserMac/AppState.swift").read()
enum = src[src.index("enum Vibscape"):]
enum = enum[:enum.index("var displayName")]
app = set(re.findall(r"case\s+([a-zA-Z]+(?:\s*,\s*[a-zA-Z]+)*)", enum))
app = {c.strip() for group in app for c in group.split(",")} - {"autoScan"}
html = open(f"{root}/site/index.html").read()
site = set(re.findall(r'data-vibscape="([a-zA-Z]+)"', html))
missing, extra = sorted(app - site), sorted(site - app)
if missing or extra:
    if missing: print("Vibscapes missing from site/index.html:", ", ".join(missing))
    if extra: print("site/index.html lists vibscapes the app doesn't have:", ", ".join(extra))
    sys.exit(1)
print(f"site/index.html covers all {len(app)} vibscapes")

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

# Each vibscape also needs its share page (with full og:* tags, so the
# recipient's chat app renders the right title and per-vibescape image) and
# its share graphic (the canvas the og:image points at). A vibscape is only
# shareable when both are present — a missing HTML means the link 404s, a
# missing JPG means crawlers see no preview.
import os
# Files that live in `site/share/` but aren't per-vibscape: the JS/CSS/JSON
# share-page machinery and `index.html` (a copy of `site/share.html` that
# serves `/share/` via Cloudflare's directory-index resolution). Skipping
# those stops the check from flagging infra as a missing vibescape.
NON_VIBSCAPE_BASENAMES = {"index", "share-page", "manifest", "share"}
missing_share, extra_share = [], []
for slug in sorted(site):
    html_path = f"{root}/site/share/{slug}.html"
    jpg_path  = f"{root}/site/share/{slug}.jpg"
    if not os.path.exists(html_path): missing_share.append(f"{slug}.html")
    if not os.path.exists(jpg_path):  missing_share.append(f"{slug}.jpg")
share_dir = f"{root}/site/share"
if os.path.isdir(share_dir):
    for entry in os.listdir(share_dir):
        if not entry.endswith((".html", ".jpg")):
            continue
        slug = entry.rsplit(".", 1)[0]
        if slug in NON_VIBSCAPE_BASENAMES:
            continue
        if slug not in site:
            extra_share.append(entry)
if missing_share or extra_share:
    if missing_share: print("Share files missing for some vibscapes:", ", ".join(sorted(missing_share)))
    if extra_share:   print("site/share/ has files for vibscapes not on the homepage:", ", ".join(sorted(extra_share)))
    sys.exit(1)
print(f"site/share/ covers all {len(site)} vibscapes")
PY
