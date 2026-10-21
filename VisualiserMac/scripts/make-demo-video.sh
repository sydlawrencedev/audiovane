#!/usr/bin/env bash
# Renders every built-in vibescape and assembles them into the homepage video.
#
# Two steps, on purpose. The app writes numbered PNGs, and ffmpeg turns those
# into an mp4. Keeping them apart means a re-render of one vibescape doesn't
# mean re-rendering eighteen, and it means the encoding settings can be changed
# without a Swift rebuild.
#
# The frames come from the same draw and the same palette grade the app uses, so
# the video is the app, not a mock-up of it.
#
#   ./scripts/make-demo-video.sh [outfile]
#
# Needs ffmpeg on the PATH. Defaults to site/media/demo.mp4, and keeps the
# previous video until the new one has been made and checked.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$here/build/Vibresia.app/Contents/MacOS/Vibresia"
# The site is a sibling of the app, not inside it.
site="$(cd "$here/.." && pwd)"
frames_dir="${FRAMES_DIR:-/tmp/vib_video}"
out="${1:-$site/site/media/demo.mp4}"

# The video is shown inside `.wrap`, which caps at 1120px and pads to 20px, so
# the largest it ever renders is 1080 CSS px. At 960 the source was being
# upscaled even on a non-retina screen. 1280 leaves headroom for a 2x display
# without paying for the full 2160.
#
# Both numbers have to be even. yuv420p halves the chroma planes, so an odd
# height is not a rounding detail — libx264 refuses to open and the whole
# render is wasted, which is why it is checked below rather than discovered at
# the last step.
width=1280
height=844
fps=30
seconds=2.0          # per vibescape
fade=0.4            # cross-dissolve length
# These visuals are procedural and very high-frequency in places, which is the
# worst case for h264. CRF was 34 here, which is close to "whatever fits": the
# result was 627 kb/s for smooth moving gradients, and gradients are exactly
# what that destroys first — the banding and mosquito noise read as blur even
# though the frame is the right size. 21 spends the bits where they show.
#
# CRF is the knee of the curve rather than a bitrate because the clips differ
# so much from each other: a single number of kb/s would starve Nyan and waste
# space on Warp. The shorter per-vibescape clip pays for most of the extra
# quality — nobody watches eighteen vibescapes for three seconds each.
crf="${CRF:-21}"
# slow buys noticeably better compression than medium at the same CRF here,
# because there is a lot of fine high-frequency detail for it to spend time on.
preset="${PRESET:-slow}"

if [ ! -x "$app" ]; then
  echo "No app at $app — run ./build-app.sh release first." >&2
  exit 1
fi
command -v ffmpeg >/dev/null || { echo "ffmpeg is not installed." >&2; exit 1; }

# Checked before rendering rather than at the encoder: an odd dimension costs
# the whole render, and the error it produces mentions libx264 rather than the
# number that is actually wrong.
if [ $(( width % 2 )) -ne 0 ] || [ $(( height % 2 )) -ne 0 ]; then
  echo "Video size ${width}x${height} has an odd dimension. yuv420p needs both even." >&2
  exit 1
fi

echo "==> Rendering frames at ${width}x${height}, ${fps}fps, ${seconds}s each"
rm -rf "$frames_dir"
mkdir -p "$frames_dir"
"$app" --video "$frames_dir" \
       --video-size "${width}x${height}" \
       --video-fps "$fps" \
       --video-seconds "$seconds" 2>&1 | grep '\[VIDEO\]' || true

if [ ! -s "$frames_dir/_order.txt" ]; then
  echo "No frames were rendered." >&2
  exit 1
fi

# macOS still ships bash 3.2, which has no mapfile.
order=()
# `|| [ -n "$line" ]` so the last entry counts even without a trailing newline,
# which is exactly how a shell-written file loses its final vibescape.
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] && order+=("$line")
done < "$frames_dir/_order.txt"
echo "==> ${#order[@]} vibescapes"

# Each clip becomes its own intermediate, because the cross-dissolve filter
# needs one input per clip and you can't feed it an image sequence.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
inputs=()
for i in "${!order[@]}"; do
  clip="${order[$i]}"
  count=$(find "$frames_dir" -name "${clip}_*.png" | wc -l | tr -d ' ')
  if [ "$count" -lt 2 ]; then
    echo "  !! $clip has $count frames, skipping" >&2
    continue
  fi
  ffmpeg -loglevel error -y \
    -framerate "$fps" -start_number 0 -i "$frames_dir/${clip}_%05d.png" \
    -c:v libx264 -preset "$preset" -crf "$crf" -pix_fmt yuv420p \
    -r "$fps" "$work/$(printf '%02d' "$i").mp4"
  inputs+=("$work/$(printf '%02d' "$i").mp4")
done

if [ "${#inputs[@]}" -lt 2 ]; then
  echo "Need at least two clips to make a video." >&2
  exit 1
fi

# Chain the dissolves. Each xfade overlaps the tail of the running reel with
# the head of the next clip, so the offset is where the previous one ended.
echo "==> Cross-dissolving ${#inputs[@]} clips (${fade}s)"
args=()
filter=""
prev="0:v"
for i in $(seq 1 $((${#inputs[@]} - 1))); do
  args+=(-i "$work/$(printf '%02d' "$i").mp4")
  # The clip is `seconds` long; after `i` overlaps the running reel is
  # i*seconds - i*fade long, so this clip must start fading in that far before
  # the end.
  offset=$(awk "BEGIN{printf \"%.3f\", $i * ($seconds - $fade)}")
  filter+="[$prev][$i:v]xfade=transition=fade:duration=$fade:offset=$offset[v$i];"
  prev="v$i"
done

# The site loops the video, so the jump from the last vibescape back to the
# first is a cut. Dissolving back into the opening clip before the end closes
# it: the reel finishes mid-fade into vibescape one, and looping lands on that
# same fade rather than on a hard cut.
if [ "${#inputs[@]}" -ge 2 ]; then
  inputs+=("${inputs[0]}")
  args+=(-i "${inputs[0]}")
  last=$((${#inputs[@]} - 1))
  offset=$(awk "BEGIN{printf \"%.3f\", $last * ($seconds - $fade)}")
  filter+="[$prev][$last:v]xfade=transition=fade:duration=$fade:offset=$offset[vloop];"
  prev="vloop"
fi

tmp_out="$work/demo.mp4"
ffmpeg -loglevel error -y \
  -i "${inputs[0]}" "${args[@]}" \
  -filter_complex "$filter" -map "[$prev]" \
  -c:v libx264 -preset "$preset" -crf "$crf" -pix_fmt yuv420p \
  -movflags +faststart \
  "$tmp_out"

# Only replace the live file once the new one has been made. If ffmpeg produced
# something broken, the site keeps working.
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$tmp_out")
size=$(wc -c < "$tmp_out" | tr -d ' ')
if [ -z "$duration" ] || [ "${duration%.*}" -lt 5 ]; then
  echo "Refusing to install a ${duration}s video." >&2
  exit 1
fi

cp "$tmp_out" "$out"

# The poster is the reel's own first frame, so the page doesn't flash a
# different vibescape before the video starts. Kept separate from share.jpg,
# which is the social card and shouldn't change just because the reel did.
poster="$site/site/media/poster.jpg"
if ffmpeg -loglevel error -y -i "$out" -frames:v 1 -q:v 3 "$poster"; then
  echo "==> Poster from the reel's first frame -> $(basename "$poster")"
fi

echo "==> Wrote $out"
echo "    $(printf '%.1f' "$duration")s, $(( size / 1024 )) kB, ${width}x${height}, ${fps}fps"

# The small clip the page paints first is derived from the finished reel rather
# than rendered alongside it. Two reasons, both load-bearing:
#
#   - Identical frames at identical timestamps. That is what lets the page
#     crossfade from one to the other without a visible jump. Two independent
#     renders would drift by a frame here and there and the swap would read as
#     a stutter.
#   - One re-encode instead of eighteen, and no second pass over the renderer.
#
# Scale to an even width (scale=-2 rounds down to the nearest even number) for
# the same yuv420p reason as the reel itself.
low_width="${LOW_WIDTH:-640}"
low_crf="${LOW_CRF:-30}"
low_out="$(dirname "$out")/demo-low.mp4"
if [ $(( low_width % 2 )) -eq 0 ] && ffmpeg -loglevel error -y -i "$out" \
     -vf "scale=${low_width}:-2" \
     -c:v libx264 -preset "$preset" -crf "$low_crf" -pix_fmt yuv420p \
     -movflags +faststart "$work/demo-low.mp4"; then
  cp "$work/demo-low.mp4" "$low_out"
  low_size=$(wc -c < "$low_out" | tr -d ' ')
  echo "==> Low-def reel -> $(basename "$low_out")"
  echo "    $(printf '%.1f' "$duration")s, $(( low_size / 1024 )) kB, ${low_width}px wide"
else
  echo "WARNING: low-def reel failed — the page will fall back to the full one." >&2
fi
