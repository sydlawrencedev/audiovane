#!/bin/bash
# Two things that can both leave PostHog empty while everything looks fine:
#
#   1. The site carrying a stale key, so events land in another project.
#   2. Both surfaces sending the wrong *shape* to /batch/.
#
# (2) is the one that hides. `/batch/` wants a JSON array of events. Both
# surfaces used to wrap the array as {"api_key": …, "batch": [ … ]}, which
# PostHog parses, answers with 200 and {"status":"Ok"}, and records nothing —
# because the object it looks at has no `event` field. Every status code said
# fine. That is why this checks the body, not just the key.
#
# VisualiserMac/.env is the source of truth for the key (build-app.sh bakes it
# into Info.plist). Runs as part of release.sh, same as check-vibscapes.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "$ROOT/scripts/check-posthog-key.py" "$ROOT"
python3 "$ROOT/scripts/check-posthog-batch.py" "$ROOT"
