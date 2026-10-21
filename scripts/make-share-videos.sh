#!/usr/bin/env bash
# Renders a short looping clip of every built-in vibescape for its share page.
#
# The share pages used to show a still. A still of a vibescape that moves is a
# lie by omission — a tunnel that doesn't tunnel — so each page now plays a few
# seconds of the real thing, rendered by the app itself and encoded here.
#
# The JPEG stays, in two places that matter: as the video's poster, so there's
# a frame from the first paint, and as the page's og:image, because a crawler
# fetching a link gets no video and runs no JavaScript.
#
#   ./scripts/make-share-videos.sh [slug …]
#
# Needs a release build and ffmpeg. With no arguments it does every built-in in
# site/share/manifest.json. Naming slugs re-renders only those, which is the
# point when you've changed one shader.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/VisualiserMac/build/Vibresia.app/Contents/MacOS/Vibresia"
manifest="$root/site/share/manifest.json"
out_dir="$root/site/share"

# The share pages are 1200x630, so the clip is that shape rather than the
# homepage's — object-fit would letterbox it otherwise.
width=1200
height=630
fps=30
seconds=4.0
crf="${CRF:-32}"
preset=medium

if [ ! -x "$app" ]; then
  echo "No app at $app — run VisualiserMac/build-app.sh release first." >&2
  exit 1
fi
command -v ffmpeg >/dev/null || { echo "ffmpeg is not installed." >&2; exit 1; }
[ -s "$manifest" ] || { echo "No $manifest — run scripts/generate-share-pages.py." >&2; exit 1; }

slugs=("$@")
if [ ${#slugs[@]} -eq 0 ]; then
  while IFS= read -r s; do slugs+=("$s"); done < <(
    python3 -c "import json,sys; [print(v['slug']) for v in json.load(open('$manifest'))['built_ins']]"
  )
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "==> ${#slugs[@]} vibescapes, ${width}x${height}, ${seconds}s each, looping"
made=0
for slug in "${slugs[@]}"; do
  frames="$work/$slug"
  rm -rf "$frames"; mkdir -p "$frames"

  # One vibescape per run: --video-only keeps this from paying for all of them.
  "$app" --video "$frames" \
         --video-size "${width}x${height}" \
         --video-fps "$fps" \
         --video-seconds "$seconds" \
         --video-only "$slug" >/dev/null 2>&1 || true

  # The app numbers its frame prefixes, so "00_ribbons" rather than "ribbons".
  # Read it rather than assuming — the numbering is the app's business.
  prefix=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *_$slug) prefix="$line" ;;
    esac
  done < "$frames/_order.txt"
  if [ -z "$prefix" ]; then
    echo "  !! $slug produced no frame prefix" >&2
    continue
  fi

  count=$(find "$frames" -name "${prefix}_*.png" | wc -l | tr -d ' ')
  if [ "$count" -lt 2 ]; then
    echo "  !! $slug rendered $count frames, skipping" >&2
    continue
  fi

  # Straight to a temp name, then moved into place: a half-written mp4 in the
  # site directory is a broken share page for anyone who lands on it mid-build.
  ffmpeg -loglevel error -y \
    -framerate "$fps" -start_number 0 -i "$frames/${prefix}_%05d.png" \
    -c:v libx264 -preset "$preset" -crf "$crf" -pix_fmt yuv420p \
    -movflags +faststart \
    "$work/$slug.mp4"

  size=$(wc -c < "$work/$slug.mp4" | tr -d ' ')
  mv "$work/$slug.mp4" "$out_dir/$slug.mp4"
  made=$((made + 1))
  printf '  %-12s %3d frames  %5d kB\n' "$slug" "$count" "$((size / 1024))"
done

total=$(du -ch "$out_dir"/*.mp4 2>/dev/null | tail -1 | awk '{print $1}')
echo "==> $made clips written to $out_dir (${total:-0} total)"
echo "    Re-run generate-share-pages.py if you changed the template."
