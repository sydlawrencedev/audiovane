#!/bin/bash
# Fails if the landing page's vibescape cards (data-vibescape="…" in site/index.html)
# don't match the app's vibescapes, or if the version in its structured
# data has drifted from VisualiserMac/VERSION. Both are things that go stale
# quietly, so both are checked at release time.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import re, sys
root = sys.argv[1]
src = open(f"{root}/VisualiserMac/Sources/VisualiserMac/AppState.swift").read()
enum = src[src.index("enum Vibescape"):]
enum = enum[:enum.index("var displayName")]
app = set(re.findall(r"case\s+([a-zA-Z]+(?:\s*,\s*[a-zA-Z]+)*)", enum))
app = {c.strip() for group in app for c in group.split(",")} - {"autoScan"}
html = open(f"{root}/site/index.html").read()
site = set(re.findall(r'data-vibescape="([a-zA-Z]+)"', html))
missing, extra = sorted(app - site), sorted(site - app)
if missing or extra:
    if missing: print("Vibescapes missing from site/index.html:", ", ".join(missing))
    if extra: print("site/index.html lists vibescapes the app doesn't have:", ", ".join(extra))
    sys.exit(1)
print(f"site/index.html covers all {len(app)} vibescapes")

# Every vibescape on the home page links to its own page, and the page
# shows the first four of them. The rest are still in the markup, because
# that is where the share pages get their names and descriptions from.
links = re.findall(r'class="vibescape" data-vibescape="([a-zA-Z]+)" '
                   r'href="/share/([a-zA-Z]+)"', html)
wrong = [(a, b) for a, b in links if a != b]
if wrong:
    print("the home page sends a vibescape to the wrong page:", wrong[0])
    sys.exit(1)
missing_links = sorted(app - {slug for slug, _ in links})
if missing_links:
    print("No link to the page for:", ", ".join(missing_links))
    sys.exit(1)
if "nth-child(n+5)" not in html:
    print("The home page is not hiding the vibescapes past the first four.")
    sys.exit(1)
print(f"the home page shows four of them, and every one links to its own page")

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

# Each vibescape also needs its share page (with full og:* tags, so the
# recipient's chat app renders the right title and per-vibescape image) and
# its share graphic (the canvas the og:image points at). A vibescape is only
# shareable when both are present — a missing HTML means the link 404s, a
# missing JPG means crawlers see no preview.
import os

# Every built-in also needs a picture. The app ships them in its bundle so
# that View All shows what a vibescape looks like; a missing one leaves the
# card as a generated cover, and nothing else breaks.
missing_pictures = [slug for slug in sorted(app)
                    if not os.path.exists(f"{root}/site/media/modes/{slug}.jpg")]
if missing_pictures:
    print("No picture for:", ", ".join(missing_pictures))
    sys.exit(1)
print(f"every vibescape has a picture ({len(app)})")
# Files that live in `site/share/` but aren't per-vibescape: the JS/CSS/JSON
# share-page machinery and `index.html` (a copy of `site/share.html` that
# serves `/share/` via Cloudflare's directory-index resolution). Skipping
# those stops the check from flagging infra as a missing vibescape.
NON_VIBESCAPE_BASENAMES = {"index", "share-page", "manifest", "share"}
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
        if slug in NON_VIBESCAPE_BASENAMES:
            continue
        if slug not in site:
            extra_share.append(entry)
if missing_share or extra_share:
    if missing_share: print("Share files missing for some vibescapes:", ", ".join(sorted(missing_share)))
    if extra_share:   print("site/share/ has files for vibescapes not on the homepage:", ", ".join(sorted(extra_share)))
    sys.exit(1)
print(f"site/share/ covers all {len(site)} vibescapes")
PY
