#!/bin/bash
# Publishes a release of AudioVane:
#   1. checks the landing page lists every visualiser mode,
#   2. builds the release app and zips it as AudioVane.zip,
#   3. creates GitHub release v$VERSION (VERSION file) with the zip attached.
# The installer and the in-app update checker always fetch the latest
# release's AudioVane.zip, so publishing here ships the update.
#
# Usage: ./release.sh            (bump VERSION first)
#        NOTES="What changed" ./release.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REPO="sydlawrencedev/audiovane"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"

../scripts/check-modes.sh

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    echo "Release $TAG already exists — bump VERSION first." >&2
    exit 1
fi

./build-app.sh release
rm -rf dist && mkdir dist
ditto build/VisualiserMac.app dist/AudioVane.app
(cd dist && ditto -c -k --keepParent AudioVane.app AudioVane.zip)

gh release create "$TAG" dist/AudioVane.zip -R "$REPO" \
    --title "AudioVane $VERSION" \
    --target "$(git rev-parse HEAD)" \
    --notes "${NOTES:-Install or update: https://audiovane.minithlabs.com}"
echo "Released $TAG"
