#!/bin/bash
# AudioVane installer — https://audiovane.minithlabs.com
# Downloads the latest release from GitHub, installs AudioVane.app into
# /Applications (or ~/Applications if that isn't writable) and opens it.
set -euo pipefail

URL="https://github.com/sydlawrencedev/audiovane/releases/latest/download/AudioVane.zip"
COFFEE="https://buy.stripe.com/fZu14mb8B9Li9Xd5BObEA00"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "AudioVane is a macOS app." >&2; exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
    echo "AudioVane currently needs an Apple silicon Mac." >&2; exit 1
fi
ver="$(sw_vers -productVersion)"
major="${ver%%.*}"; rest="${ver#*.}"; minor="${rest%%.*}"
if [ "$major" -lt 14 ] || { [ "$major" -eq 14 ] && [ "${minor:-0}" -lt 2 ]; }; then
    echo "AudioVane needs macOS 14.2 or later (this Mac has $ver)." >&2; exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading AudioVane…"
curl -fsSL "$URL" -o "$tmp/AudioVane.zip"
ditto -x -k "$tmp/AudioVane.zip" "$tmp"

dest="/Applications/AudioVane.app"
if [ ! -w /Applications ]; then
    mkdir -p "$HOME/Applications"
    dest="$HOME/Applications/AudioVane.app"
fi
osascript -e 'tell application id "com.minithlabs.visualiser" to quit' >/dev/null 2>&1 || true
rm -rf "$dest"
mv "$tmp/AudioVane.app" "$dest"
# The app is ad-hoc signed rather than notarised, so clear the download
# quarantine flag or Gatekeeper will refuse to open it.
xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
open "$dest"

echo ""
echo "AudioVane is installed at $dest and opening now."
echo "Click 'Share System Audio' and allow system audio recording when macOS asks."
echo "It updates itself whenever there's a new version."
echo ""
echo "AudioVane is free and open source. If you enjoy it, please buy the developer a coffee: $COFFEE"
echo "Found a bug or have an idea? File an issue: https://github.com/sydlawrencedev/audiovane/issues"
echo "Pull requests are very welcome, especially new visualisations: https://github.com/sydlawrencedev/audiovane/blob/main/CONTRIBUTING.md"
