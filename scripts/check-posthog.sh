#!/bin/bash
# Fails if the landing page's PostHog key doesn't match the app's.
#
# Both surfaces report into one PostHog project, so the site can't carry a
# stale key: the events would land in whatever project that key belongs to and
# the dashboard would quietly show half the data. VisualiserMac/.env is the
# source of truth (it's also what build-app.sh bakes into Info.plist).
#
# Runs as part of release.sh, same as check-vibscapes.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]

env = os.path.join(root, "VisualiserMac/.env")
html = open(os.path.join(root, "site/index.html")).read()

def from_env():
    if not os.path.exists(env):
        print(f"VisualiserMac/.env is missing — can't check the analytics key.")
        sys.exit(1)
    for line in open(env):
        m = re.match(r'\s*POSTHOG_KEY\s*=\s*"?([A-Za-z0-9_]+)"?', line)
        if m:
            return m.group(1)
    print("VisualiserMac/.env has no POSTHOG_KEY.")
    sys.exit(1)

site = re.search(r'<meta name="posthog-key" content="([^"]*)"', html)

key = from_env()
if not site or not site.group(1):
    print("site/index.html has no <meta name=\"posthog-key\"> — the landing page won't report.")
    sys.exit(1)
if site.group(1) != key:
    print("PostHog key mismatch:")
    print(f"  VisualiserMac/.env : {key}")
    print(f"  site/index.html    : {site.group(1)}")
    print("Update the meta tag to match .env (the site key is public by design).")
    sys.exit(1)
print(f"site and app share PostHog project {key[:8]}…")
PY