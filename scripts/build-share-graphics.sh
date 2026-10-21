#!/usr/bin/env bash
# Draws the website's share picture for every built-in vibescape.
#
#   ./scripts/build-share-graphics.sh
#
# The drawing itself lives in the app's package
# (VisualiserMac/Sources/ShareGraphics), because the brand it draws has to be
# the same brand the app draws on the share image it uploads. It used to be a
# script with its own copy of the logo, which is how the built-in pictures
# ended up with a different mark in the corner from the app's own.
#
# Idempotent: existing files are overwritten. Re-run any time a vibescape's
# picture changes, or after adding a new vibescape to the share manifest.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# The tool takes the repo root so it can be run from anywhere.
swift run --package-path VisualiserMac ShareGraphics "$root"
