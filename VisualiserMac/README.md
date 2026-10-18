# AUDIVANE

A native macOS audio visualizer in the spirit of late-90s/early-2000s Winamp. Reads system audio directly, no browser, no fake "screen-share with audio" hack.

Twelve modes:

1. **Tunnel**: fly through concentric rings of spectrum-reactive bars.
2. **Constellation**: 4,000 bass-pumping particles around you.
3. **Liquid**: Milkdrop-inspired psychedelic fluid that flows to the music.
4. **Badger Badger**: rows of badgers pop up and dance, then a mushroom, then a snake.
5. **Whooping Llama**: dancing llamas in blankets, whooping on every beat.
6. **Hamster Dance**: a scrolling wall of dancing hamsters. Drop your own animated GIFs (or APNG/PNG) into `~/Library/Application Support/AUDIVANE/Hamsters/` (**Visualizer → Open Hamster Folder…**) and they replace the drawn hamsters: tiled edge to edge at native pixels (integer-scaled), animating at their own frame timing and bouncing on the beat. Up to 16 images; the folder is re-checked every couple of seconds.
7. **Nyan Cat**: pixel cat on a rainbow trail through the stars.
8. **Spectrum**: classic segmented LED spectrum bars.
9. **Kaleidoscope**: mirrored fractal folds that punch in on the bass.
10. **Warp**: hyperspace star streaks.
11. **The Band**: five Game Boy–style pixel musicians (drums, bass, guitar, keys, vocals). Apple's on-device sound classifier (SoundAnalysis) decides who is playing, and they get a spotlight. Spectrum onsets time the kick, snare and hi-hat hits, strums, bass plucks, key presses and singing. Anyone not heard stands at rest.
12. **Machine**: a port of the MIDEM Music Hack Day piece by [@mrdoob and @plamere](https://github.com/mrdoob/midemhackday) — a corridor of drums and a ring of pads, with note events launching bouncing balls that arc over the drums; the struck drum recoils and flashes white. The camera flies a 48-second loop through both machines.
13. **Auto Scan**: cycles through every other mode, 20 seconds each.

Modes 4–10 are full-screen fragment shaders in `Render/FunShaders.swift`, drawn procedurally (no image assets). Mode 12 (`Machine`) is instanced 3D geometry in `Render/MachineRenderer.swift`.

Built with SwiftUI + OpenGL 3.3 + Core Audio process taps + Accelerate (vDSP).

## Running

The bundle is self-contained at `build/VisualiserMac.app`. To open it:

```
open build/VisualiserMac.app
```

Or to rebuild first:

```
./build-app.sh debug      # debug build at build/VisualiserMac.app
./build-app.sh release    # release build
```

Then click **Share System Audio** in the intro screen and pick the tab/app playing audio (Spotify, YouTube, etc.). macOS will ask for screen-recording permission — that's what gives us access to the audio.

Other sources:
- **Use Microphone** — visualizes whatever the mic hears.
- **Use Demo Tone** — synthesized kick + sweep, so you can see it work without sharing anything.

## Header controls

Everything lives in the top bar so the visualiser gets the whole window:

- **Mode picker** (left of the group) — all twelve modes in a drop-down. Each
  row shows its number-row shortcut, so the keyboard route stays discoverable
  now that the list isn't permanently on screen.
- **Genre picker** — only in band mode (or when Auto Scan is sitting on the
  band), since the genre drives the stage, the lineup and the palette there.
  Clicking a genre locks it for the current song; the next song re-arms auto.
  The confidence bar next to the name shows how sure the detector is.
- **Source pill** and **BPM** readout.

Click away from an open list to dismiss it.

## Keyboard shortcuts

- `1`–`9`, `0`, `-` — switch visualiser mode
- `=` — auto scan
- `Space` / `Esc` — toggle the intro overlay

## Development flags

- `--mode <name>` — start in a given mode (e.g. `--mode machine`)
- `--autoscan` — start in auto scan
- `--scan-seconds N` — shorten the auto-scan dwell time (default 20s)
- `--snapshot` — render one frame of every mode to PNG and exit
- `--snapshot --genres` — render one frame of every genre and exit
- `--ui-shot` — render the SwiftUI chrome to PNG (the OpenGL layer won't appear)
- `--record <dir>` — capture consecutive frames of the GL output
- `MACHINE_CAM="ex,ey,ez,tx,ty,tz"` — pin the machine mode's camera

## Band mode: 10 genres

Press `-` to enter **THE BAND**. The genre pill in the top bar switches the whole
scene — the room, the palette, the strobing, and which musicians are on stage.

| Genre | Room | Band |
|-------|------|------|
| Classical | Concert hall, columns, spotlights, marley floor | Strings + piano + singer |
| Electronic | Dark booth, cyan/magenta neon, beat strobe | Just the DJ |
| Rock | Velvet theatre, amp stacks, footlights | Full band |
| Pop | Clean studio, pink/purple, mic stand | Full band |
| Hip-Hop | Brick wall, gold chain, concrete floor | Drums + 808 + DJ + MC |
| Jazz | Smoky club, single spotlight | Bass + piano + horn + singer |
| Blues | Dim bar, neon sign, wood counter | Guitar + two singers |
| Country | Daylight porch, sunlit window | Upright bass + guitar + two singers |
| R&B | Purple velvet, gold tassels, spotlights | Full band |
| Ambient | No stage — a pastel soundscape | *Nobody* |

**Genre detection** is on by default. A `GenreDetector` watches a 15-second
window of BPM, bass/mid/treble, spectral centroid, onset density, dynamic
range and vocal presence, and scores all ten genres against distinctive
signatures. Click a genre to lock it — it stays until the next song, then
auto re-engages. Your last choice persists across launches.

The confidence bar next to the genre name is honest: it shows the *margin*
between the winner and the runner-up, not the raw score. Amber means the
detector is still deciding and won't swap the stage on its own yet; cyan means
it has committed.

**The band stays on stage.** On a song change nobody walks off — each musician
gets a 10-second grace to be re-confirmed by the new song, and if their
instrument hasn't been heard by then they leave. On a genre change, musicians
whose instrument isn't in the new genre's lineup walk off immediately.

## Testing the genre detector

The scoring rules live in `Sources/VisualiserMac/Band/GenreDetector.swift` and
are mirrored in a standalone harness so they can be checked without running the
app:

```
python3 Tests/test_detector.py
```

15 synthetic feature-sets, one per genre plus the awkward overlaps (128bpm
Electronic vs Rock, 75bpm Blues vs Country, tempo-less ballad vs Ambient).
`Tests/test_detector.py` must be kept in sync with the Swift rules.

## Keyboard shortcuts

- `1`–`9`, `0`, `-` — switch mode (`0` is Warp, `-` is The Band)
- `Space` / `Esc` — toggle intro overlay

## Implementation notes

- `App.swift` — SwiftUI entry point + `AppDelegate` for snapshot/cleanup hooks.
- `Audio/AudioEngine.swift` — orchestrates sources and analysis; publishes `AudioSnapshot` for the renderer.
- `Audio/AudioAnalyzer.swift` — 2048-point vDSP FFT, log-binned spectrum, adaptive beat detection, BPM from onset intervals.
- `Audio/SystemAudioCapture.swift` — Core Audio process tap → private aggregate device → IOProc. Requires macOS 14.2+.
- `Audio/DemoTone.swift` — synthesized demo source.
- `Audio/AudioRingBuffer.swift` — lock-free SPSC ring buffer between audio and render threads.
- `Render/OpenGLRenderer.swift` — 3.3 Core profile renderer, three pipelines, per-frame uniform/buffer upload.
- `Render/Shaders.swift` — embedded GLSL 330 core shaders (tunnel / particles / liquid).
- `UI/OpenGLView.swift` — `NSOpenGLView` subclass wrapped in `NSViewRepresentable`.

## Why OpenGL?

Metal needs Xcode's `metalc` toolchain. This repo uses Swift Package Manager without Xcode, so the build falls back to OpenGL (which Apple still ships with every macOS). Performance is fine for 60fps at 1280×720. All visuals run on the GPU via shaders.

## Verifying headlessly

For visual regression / sanity checks:

```
SNAPSHOT_DIR=/tmp/viz_snapshots ./build/VisualiserMac.app/Contents/MacOS/VisualiserMac --snapshot
```

This renders one frame of each mode to PNG and exits.