#!/bin/bash
# Computes the build version from today's date.
#
#   MAJOR.MINOR.PATCH
#
#   MAJOR   years since 2026
#   MINOR   the month, 1-12
#   PATCH   the day of the month (two digits) followed by the build number
#           of that day
#
# So 0.10.201 is 2026, October, the 20th, the first build of that day.
# Versions sort in the order they were built, which is the whole point:
# nobody has to remember to bump a number.
#
# Usage:
#   version.sh            print the version
#   version.sh --write    print it, and record it in VERSION and on the
#                          landing page, so a release matches the app
#
# The build number of the day is kept in build/.build-count, which is
# gitignored along with the rest of the build output. It starts again at 1
# on each new day.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The year the scheme starts counting from.
EPOCH_YEAR=2026

today="$(date '+%Y %m %d')"
year="${today%% *}"
rest="${today#* }"
month="${rest%% *}"
day="${rest##* }"

major=$(( year - EPOCH_YEAR ))

# How many builds have happened today. The state file holds the day it was
# last touched and the count, so a new day starts again at one.
state="$SCRIPT_DIR/build/.build-count"
build=1
if [ -f "$state" ]; then
    read -r last_day last_build < "$state" || true
    if [ "${last_day:-}" = "$day" ] && [ -n "${last_build:-}" ]; then
        build=$(( last_build + 1 ))
    fi
fi
mkdir -p "$(dirname "$state")"
printf '%s %s\n' "$day" "$build" > "$state"

VERSION="$major.$month.$day$build"

if [ "${1:-}" = "--write" ]; then
    printf '%s\n' "$VERSION" > "$SCRIPT_DIR/VERSION"
    # The landing page states the version in its structured data, and
    # scripts/check-vibescapes.sh fails the release if the two drift apart.
    site="$SCRIPT_DIR/../site/index.html"
    if [ -f "$site" ]; then
        python3 - "$site" "$VERSION" <<'PY'
import re, sys
path, version = sys.argv[1], sys.argv[2]
html = open(path).read()
new, n = re.subn(r'("softwareVersion":\s*")[^"]*(")', r'\g<1>' + version + r'\g<2>', html, count=1)
if n == 0:
    print("warning: no softwareVersion in " + path, file=sys.stderr)
else:
    open(path, "w").write(new)
PY
    fi
fi

printf '%s\n' "$VERSION"
