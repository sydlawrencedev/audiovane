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
node ../scripts/check-admin-page.mjs
../scripts/check-posthog.sh
../scripts/check-no-webhook-leak.sh
# The share page embeds a copy of the app's shaders, because a browser can't
# reach the app to ask for them. That copy has to move with the original.
../scripts/check-preview-glsl.py
# And the two copies of the vibescape reference — the app's MCP server and
# the website's public one — have to say the same thing, or an agent is told
# different things depending on which it asked.
python3 ../scripts/check-mcp-reference.py
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

# Was it signed with a real identity, or ad-hoc?
#
# build-app.sh signs ad-hoc when there is no Developer ID certificate in the
# keychain, and ad-hoc is what this has always done. A Developer ID signature
# is a different thing: macOS trusts the identity, so Gatekeeper stops asking
# for an override — but only if the app also carries a notarization ticket.
# Signed but not notarized is the worst of the two. Gatekeeper refuses it
# with "cannot be opened because the developer cannot be verified", and the
# way past that is in Privacy & Security, rather than the one-click override
# an ad-hoc build gets, which install.sh handles by clearing the quarantine
# flag.
#
# The authorities are read into a variable rather than piped into grep -q.
# grep -q exits the moment it finds a match, which closes the pipe while
# codesign is still writing; codesign then dies of SIGPIPE, and with
# pipefail on the whole pipeline reads as a failure — so the check would say
# "not signed with an identity" for an app that is, and the release would
# quietly skip notarization.
SIGNED_WITH_IDENTITY=0
SIGNATURE_AUTHORITIES="$(codesign -dv --verbose=4 build/Vibresia.app 2>&1 || true)"
case "$SIGNATURE_AUTHORITIES" in
    *"Authority=Developer ID Application"*) SIGNED_WITH_IDENTITY=1 ;;
esac

if [ "$SIGNED_WITH_IDENTITY" -eq 1 ]; then
    # Notarization happens here, after the build and before the zip is taken,
    # because signing the bundle again is what invalidates a ticket. The
    # ticket is bound to the signature it was issued for, so a re-signed
    # bundle carries a ticket that no longer validates — and codesign still
    # reports "Notarization Ticket=stapled" afterwards, so only
    # `stapler validate` can be trusted about it.
    #
    # That is why notarize.sh used to have to run before this script, and why
    # running it there was not enough: this script rebuilds the app, which
    # threw the notarization away again. A release that was notarized by
    # hand and then published through here shipped un-notarized.
    #
    # notarize.sh submits the built app, staples the ticket onto
    # build/Vibresia.app in place and rebuilds the zip around it. The copy
    # taken below is then made from the stapled bundle, so it carries the
    # ticket: ditto preserves it, in both the directory copy and the zip.
    echo "==> Signed with a Developer ID identity — notarizing before release"
    if ! ./scripts/notarize.sh; then
        echo "ERROR: notarization failed, so this release is not going out." >&2
        echo "       A Developer ID build with no valid ticket is refused by" >&2
        echo "       Gatekeeper, so publishing it would break the install for" >&2
        echo "       everyone. Fix the failure above and run this again." >&2
        exit 1
    fi
fi

if ! xcrun stapler validate build/Vibresia.app >/dev/null 2>&1; then
    if [ "$SIGNED_WITH_IDENTITY" -eq 1 ]; then
        echo "ERROR: the app is signed with a Developer ID identity but carries" >&2
        echo "       no valid notarization ticket. Not publishing this." >&2
        exit 1
    fi
    # Without a stapled ticket the app still works for whoever built it, and
    # Gatekeeper will open it on anyone else's Mac only after Apple is
    # reachable and has notarized it. Say so rather than fail: an unsigned
    # release is a legitimate thing to push while the certificate is being
    # sorted out.
    echo "" >&2
    echo "NOTE: this build is NOT notarized. Gatekeeper will ask people to" >&2
    echo "      override it on first launch." >&2
fi

# Only the things this script replaces. `rm -rf dist` would throw away the
# notarized pkg notarize.sh leaves there.
#
# --norsrc because ditto otherwise stores attributes it cannot fit in a zip
# as AppleDouble sidecars, and those sidecars land inside the signed bundle
# when it is unpacked — which invalidates the signature. The app has no
# resource forks worth keeping, so there is nothing to lose.
mkdir -p dist
rm -rf dist/Vibresia.app dist/Vibresia.zip
ditto build/Vibresia.app dist/Vibresia.app
(cd dist && ditto -c -k --norsrc --keepParent Vibresia.app Vibresia.zip)

# The zip is the artifact everyone downloads, so check the thing that is
# actually shipped rather than the bundle it came from. Unpacking it with
# `unzip` is the harsh test: unlike ditto, unzip does not understand
# AppleDouble entries, so it leaves them behind as real files inside the
# bundle and the signature stops matching. A release that fails here is one
# where a user's install is broken, so it is worth the few seconds.
#
# If unzip is somehow not there, fall back to ditto — which is what
# install.sh uses anyway — and say so rather than blocking the release.
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
if command -v unzip >/dev/null 2>&1; then
    if ! unzip -q dist/Vibresia.zip -d "$VERIFY_DIR" 2>/dev/null; then
        echo "ERROR: the release zip could not be unpacked." >&2
        exit 1
    fi
else
    echo "NOTE: no unzip on this machine — checking the zip with ditto" >&2
    echo "      instead, which is what the installer uses anyway." >&2
    ditto -x -k dist/Vibresia.zip "$VERIFY_DIR" || exit 1
fi

# Found without a pipe: `find | grep -q` closes the pipe early, find dies of
# SIGPIPE, and with pipefail on the whole thing reads as a failure.
APPLEDOUBLE_FILES="$(find "$VERIFY_DIR" -name '._*' -print)"
if [ -n "$APPLEDOUBLE_FILES" ]; then
    echo "ERROR: the release zip contains AppleDouble files, which land" >&2
    echo "       inside the signed bundle when it is unpacked and break the" >&2
    echo "       signature. Not publishing this." >&2
    exit 1
fi
if ! codesign --verify --deep --strict "$VERIFY_DIR/Vibresia.app" 2>/dev/null; then
    echo "ERROR: the app in the release zip does not verify once unpacked." >&2
    echo "       Not publishing this." >&2
    exit 1
fi
rm -rf "$VERIFY_DIR"
trap - EXIT

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
