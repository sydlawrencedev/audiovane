#!/bin/bash
# Publishes a release of Vibresia:
#   1. checks the landing page lists every visualiser mode,
#   2. checks the landing page and the app report to the same PostHog project,
#   3. checks no Discord webhook URL has been committed, that the share
#      page's copy of the shaders hasn't drifted from the app's, and that
#      every page still carries the shared navbar and footer,
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
# Every page's navbar and footer come from site/_partials. Nothing enforces
# that by itself: three definitions of .brand is survivable, three that drift
# apart quietly is not.
python3 ../scripts/inject-chrome.py --check "$(pwd)/.."

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    echo "Release $TAG already exists — build again to get a new one." >&2
    exit 1
fi

# The version is passed on rather than recomputed, so the app in the zip
# carries the same number as the tag.
VERSION_OVERRIDE="$VERSION" REQUIRE_WATCHER=1 ./build-app.sh release

# Notarization is a separate step, on purpose: it needs an Apple Developer
# identity and notary credentials, and this release path has to keep working on
# a machine that has neither. Run scripts/notarize.sh before this, and it staples
# the ticket onto build/Vibresia.app in place — so the zip made below carries it.
#
# Without a stapled ticket the app still works for whoever built it, and Gate-
# keeper will open it on anyone else's Mac only after Apple is reachable and has
# notarized it. Say so rather than fail: an unsigned release is a legitimate
# thing to push while the certificate is being sorted out.
if ! xcrun stapler validate build/Vibresia.app >/dev/null 2>&1; then
    echo "" >&2
    echo "NOTE: this build is NOT notarized. Gatekeeper will ask people to" >&2
    echo "      override it on first launch." >&2
    echo "      Run scripts/notarize.sh first to sign and staple properly." >&2
fi

# Only the things this script replaces. `rm -rf dist` would throw away the
# notarized pkg notarize.sh leaves there.
mkdir -p dist
rm -rf dist/Vibresia.app dist/Vibresia.zip
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
