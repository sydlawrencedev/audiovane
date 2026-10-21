#!/bin/bash
# Publishes a release of Vibresia:
#   1. checks the landing page lists every visualiser mode,
#   2. checks the landing page and the app report to the same PostHog project,
#   3. checks no Discord webhook URL has been committed, and that the share
#      page's copy of the shaders hasn't drifted from the app's,
#   4. builds the release app and zips it as Vibresia.zip,
#   5. creates GitHub release v$VERSION with the zip attached.
# The installer and the in-app update checker always fetch the latest
# release's Vibresia.zip, so publishing here ships the update.
#
# The version is the build's date (see version.sh), so there's no number to
# bump: running this decides it, records it in VERSION and on the landing
# page, and tags the release with it.
#
# Usage: ./release.sh
#        NOTES="What changed" ./release.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REPO="sydlawrencedev/vibresia"
# --write records the version in VERSION and in the landing page's
# structured data, so the site and the app agree.
VERSION="$(./version.sh --write)"
TAG="v$VERSION"

../scripts/check-vibescapes.sh
../scripts/check-posthog.sh
../scripts/check-no-webhook-leak.sh
# The share page embeds a copy of the app's shaders, because a browser can't
# reach the app to ask for them. That copy has to move with the original.
../scripts/check-preview-glsl.py

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    echo "Release $TAG already exists — build again to get a new one." >&2
    exit 1
fi

# The version is passed on rather than recomputed, so the app in the zip
# carries the same number as the tag.
VERSION_OVERRIDE="$VERSION" REQUIRE_WATCHER=1 ./build-app.sh release
rm -rf dist && mkdir dist
ditto build/Vibresia.app dist/Vibresia.app
(cd dist && ditto -c -k --keepParent Vibresia.app Vibresia.zip)

# The zip is attached twice, under the current name and the one the app had
# before the rename. This is not a leftover: builds released as AudioVane
# hardcode `assetName = "AudioVane.zip"` and find updates only through
# `releases/latest`, so the old name has to stay attached or those installs
# can never update again — they'd sit on whatever they had, permanently,
# with no path forward. (The copy on the current release shows 0 downloads,
# so it's likely nobody is on one any more, but that's not provable from
# here.)
#
# Drop the `cp` and the second asset once every pre-rename install is gone.
# The signal is the download count on AudioVane.zip across recent releases
# staying at 0 — check it before removing:
#   gh release view <tag> -R sydlawrencedev/vibresia --json assets \
#     --jq '.assets[] | select(.name=="AudioVane.zip") | .downloadCount'
cp dist/Vibresia.zip dist/AudioVane.zip

gh release create "$TAG" dist/Vibresia.zip dist/AudioVane.zip -R "$REPO" \
    --title "Vibresia $VERSION" \
    --target "$(git rev-parse HEAD)" \
    --notes "${NOTES:-Install or update: https://vibresia.com}"
echo "Released $TAG"
