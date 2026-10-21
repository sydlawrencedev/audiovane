#!/bin/bash
# Three things that can each leave PostHog empty while everything looks fine:
#
#   1. The site carrying a stale key, so events land in another project.
#   2. Both surfaces sending the wrong *shape* to /batch/.
#   3. The key itself being dead — rotated, deleted, or belonging to a project
#      nobody is looking at.
#
# (2) is the one that hides. `/batch/` wants a JSON array of events. Both
# surfaces used to wrap the array as {"api_key": …, "batch": [ … ]}, which
# PostHog parses, answers with 200 and {"status":"Ok"}, and records nothing —
# because the object it looks at has no `event` field. Every status code said
# fine. That is why this checks the body, not just the key.
#
# (3) hides the same way, and worse, because no amount of static checking finds
# it: `/batch/` returns 200 {"status":"Ok"} for *any* syntactically valid
# `phc_` key, dead ones included. It only 401s when the payload has no
# api_key at all. Checks 1 and 2 are static and cannot see it — a dead key
# matches itself. Only check 3 asks the question that actually matters, by
# reading an event back, and it skips unless a personal API key is configured.
#
# VisualiserMac/.env is the source of truth for the key (build-app.sh bakes it
# into Info.plist). Runs as part of release.sh, same as check-vibscapes.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "$ROOT/scripts/check-posthog-key.py" "$ROOT"
python3 "$ROOT/scripts/check-posthog-batch.py" "$ROOT"
python3 "$ROOT/scripts/check-posthog-live.py" "$ROOT"
