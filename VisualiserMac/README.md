# AUDIOVANE

A native macOS audio visualizer in the spirit of late-90s/early-2000s Winamp. Reads system audio directly, no browser, no fake "screen-share with audio" hack.

Thirteen modes, plus Auto Scan:

1. **Tunnel**: fly through concentric rings of spectrum-reactive bars.
2. **Constellation**: 4,000 bass-pumping particles around you.
3. **Liquid**: Milkdrop-inspired psychedelic fluid that flows to the music.
4. **Badger Badger**: rows of badgers dancing to the beat; big drops bring out the mushroom (or, every third, the snake).
5. **Whooping Llama**: dancing llamas in blankets, whooping on every beat.
6. **Hamster Dance**: a scrolling wall of dancing hamsters. Drop your own animated GIFs (or APNG/PNG) into `~/Library/Application Support/AUDIOVANE/Hamsters/` (**Visualizer → Open Hamster Folder…**) and they replace the drawn hamsters: tiled edge to edge at native pixels (integer-scaled), animating at their own frame timing and bouncing on the beat. Up to 16 images; the folder is re-checked every couple of seconds.
7. **Nyan Cat**: pixel cat on a rainbow trail through the stars.
8. **Spectrum**: classic segmented LED spectrum bars.
9. **Kaleidoscope**: mirrored fractal folds that punch in on the bass.
10. **Warp**: hyperspace star streaks.
11. **The Band**: colour pixel-art musicians in ten genre sets (classical hall, DJ booth, rock theatre, pop studio, hip-hop street, jazz club, blues bar, country porch, R&B velvet, ambient), each with its own instruments and outfits. Apple's on-device sound classifier (SoundAnalysis), backed up by beat and bass detection, decides who walks on; the singer's voice (female, male or duet) comes from the vocal pitch. Playing follows the beat clock, with spectrum onsets as accents.
12. **Machine**: a port of the MIDEM Music Hack Day piece by [@mrdoob and @plamere](https://github.com/mrdoob/midemhackday), rebuilt from its source: twelve stations of lathe-turned cannons and drums (one per pitch class) and a ring of 40 pads. Each note onset fires balls that arc onto the drum and pad for that pitch and loudness; struck drums recoil and flash white. Smooth meshes, 4x MSAA with a depth buffer, and the original's camera path flown over the length of the track (Music/Spotify report it).
13. **Neon Wave**: layered glowing green waveforms, shaped by the spectrum like an analogue sound analyser.

**Auto Scan** cycles through every other mode, 20 seconds each, and always sits at the bottom of the mode list.

Modes 4–11 and 13 are full-screen fragment shaders in `Render/FunShaders.swift`, drawn procedurally (no image assets). Mode 12 (`Machine`) is instanced 3D geometry in `Render/MachineRenderer.swift`.

Built with SwiftUI + OpenGL 3.3 + Core Audio process taps + Accelerate (vDSP).

## Running

The bundle is self-contained at `build/AudioVane.app`. To open it:

```
open build/AudioVane.app
```

Or to rebuild first:

```
./build-app.sh debug      # debug build at build/AudioVane.app
./build-app.sh release    # release build
```

Then click **Share System Audio** in the intro screen and pick the tab/app playing audio (Spotify, YouTube, etc.). macOS will ask for screen-recording permission — that's what gives us access to the audio.

Other sources:
- **Use Microphone** — visualizes whatever the mic hears.
- **Use Demo Tone** — synthesized kick + sweep, so you can see it work without sharing anything.

## Colour palettes

Five palettes, picked from the header. The palette is applied as a **post-process
over the finished frame** — a duotone grade that stretches the scene's
luminance ramp between a shadow and a highlight colour, then adjusts
saturation and lifts the blacks. Because it runs after the scene rather than
inside each shader, one palette themes *every* mode at once: the tunnel, the
band, the machine, all of them.

| Palette | Look |
|---------|------|
| **NEON** | The original magenta / cyan look. |
| **EMBER** | Warm amber — embers, dust, stage light. |
| **TOXIC** | Green — oscilloscope, matrix, laboratory. |
| **ABYSS** | Cold blue — moonlight, deep water, sonar. |
| **MONO** | Greyscale. |

## Credits and support

A small **"Made with ❤️ by Minith Labs"** button sits in the bottom-right
corner. It opens a popover with a link to [minithlabs.com](https://minithlabs.com)
and a **"Buy us a coffee"** button that opens Stripe's hosted checkout in the
default browser. No card details ever touch AudioVane.

> This started life as Stripe's embedded Buy Button (the `<stripe-buy-button>`
> custom element in a `WKWebView`). It doesn't survive contact with a real app:
> the element upgrades, the iframe appears, and Stripe leaves the button stuck
> on its loading shimmer indefinitely — which on a dark popover just reads as a
> rendering bug. A native button that hands off to the same Stripe payment link
> can't half-render, and a full browser tab is a far better place to type a card
> number than a 284pt-wide iframe.

## Analytics

PostHog, wired directly to the capture endpoint — no SDK, no dependency. The
official iOS SDK also pulls in feature flags, session replay and surveys, and
session replay has no business inside an app whose entire job is capturing the
screen.

**What is sent:** which mode you switched to, which palette, the coarse genre
the detector settled on, and whether the support button got clicked.

**What is never sent:** screen content, audio, window titles, track names, file
paths, or any hardware identifier. `distinct_id` is a random UUID in
`UserDefaults` — it identifies an install, not a person.

There's a toggle at the bottom of the credits popover, and the whole subsystem
compiles out entirely with `POSTHOG_DISABLE=1`.

### Configuration

Create a `.env` next to `build-app.sh`:

```
POSTHOG_KEY=phc_xxxxxxxxxxxxxxxxxxxx
POSTHOG_HOST=https://eu.i.posthog.com
```

`POSTHOG_HOST` defaults to `https://us.i.posthog.com`. Leave `POSTHOG_KEY` empty
to ship a build with no telemetry at all — the toggle then reads "Not configured
in this build."

The project key is public by design (write-only, like Stripe's publishable key):
it can add events but never read them.

## Header controls

Everything lives in the top bar so the visualiser gets the whole window:

- **Mode picker** (left of the group) — all thirteen modes in a drop-down. Each
  row shows its number-row shortcut, so the keyboard route stays discoverable
  now that the list isn't permanently on screen.
- **Genre picker** — only in band mode (or when Auto Scan is sitting on the
  band), since the genre drives the stage, the lineup and the palette there.
  Clicking a genre locks it for the current song; the next song re-arms auto.
  The confidence bar next to the name shows how sure the detector is.
- **Palette picker** — the five colour palettes, each with its own swatch.
- **Source pill** and **BPM** readout.

Click away from an open list to dismiss it.

## Keyboard shortcuts

- `1`–`9`, `0`, `-` — switch visualiser mode
- `=` — auto scan
- `Space` / `Esc` — toggle the intro overlay

## Development flags

- `--mode <name>` — start in a given mode (e.g. `--mode machine`)
- `--palette N` — start with a given colour palette (0–4)
- `--autoscan` — start in auto scan
- `--scan-seconds N` — shorten the auto-scan dwell time (default 20s)
- `--about` — open the credits popover on launch (checks the Stripe embed)
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
SNAPSHOT_DIR=/tmp/viz_snapshots ./build/AudioVane.app/Contents/MacOS/AudioVane --snapshot
```

This renders one frame of each mode to PNG and exits.