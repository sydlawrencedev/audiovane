#!/bin/bash
# Vibresia installer — https://vibresia.com
# Downloads the latest release from GitHub, installs Vibresia.app into
# /Applications (or ~/Applications if that isn't writable) and opens it.
set -euo pipefail

REPO="sydlawrencedev/vibresia"
URL="https://github.com/$REPO/releases/latest/download/Vibresia.zip"
# The app was called AudioVane until recently, and the release it was
# published under is still called that. Both are attached to the release, so
# this only matters for the first Vibresia release.
FALLBACK_URL="https://github.com/$REPO/releases/latest/download/AudioVane.zip"
COFFEE="https://buy.stripe.com/7sY3cuekN6z66L1c0cbEA01"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Vibresia is a macOS app." >&2; exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
    echo "Vibresia currently needs an Apple silicon Mac." >&2; exit 1
fi
ver="$(sw_vers -productVersion)"
major="${ver%%.*}"; rest="${ver#*.}"; minor="${rest%%*.}"
if [ "$major" -lt 14 ] || { [ "$major" -eq 14 ] && [ "${minor:-0}" -lt 2 ]; }; then
    echo "Vibresia needs macOS 14.2 or later (this Mac has $ver)." >&2; exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading Vibresia…"
if ! curl -fsSL "$URL" -o "$tmp/Vibresia.zip"; then
    echo "Falling back to the previous release name…" >&2
    curl -fsSL "$FALLBACK_URL" -o "$tmp/Vibresia.zip"
fi
ditto -x -k "$tmp/Vibresia.zip" "$tmp"

# Where the app goes. The bundle id hasn't changed, so this replaces the
# old AudioVane in place rather than sitting beside it.
dest="/Applications/Vibresia.app"
if [ ! -w /Applications ]; then
    mkdir -p "$HOME/Applications"
    dest="$HOME/Applications/Vibresia.app"
fi
osascript -e 'tell application id "com.minithlabs.visualiser" to quit' >/dev/null 2>&1 || true
rm -rf "$dest"
# The app was called AudioVane before the rename, and the bundle id is the
# same — so the old one has to go, or there'd be two apps with the same id
# and macOS would keep opening the old one.
for old in /Applications/AudioVane.app "$HOME/Applications/AudioVane.app"; do
    if [ -d "$old" ]; then
        echo "Removing the old AudioVane…"
        rm -rf "$old"
    fi
done
mv "$tmp/Vibresia.app" "$dest"
# The app is ad-hoc signed rather than notarised, so clear the download
# quarantine flag or Gatekeeper will refuse to open it.
xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
open "$dest"

echo ""
echo "Vibresia is installed at $dest and opening now."
echo "Click 'Share System Audio' and allow system audio recording when macOS asks."
echo "It updates itself whenever there's a new version."
echo ""
echo "Vibresia is free and open source. If you enjoy it, please buy the developer a coffee: $COFFEE"
echo "Found a bug or have an idea? File an issue: https://github.com/$REPO/issues"
echo "Pull requests are very welcome, especially new visualisations: https://github.com/$REPO/blob/main/CONTRIBUTING.md"
