# VIBRESIA

A native macOS app for visual worlds that move with your music, in the spirit of late-90s/early-2000s Winamp. Reads system audio directly, no browser, no fake "screen-share with audio" hack.

The vibscapes, plus Auto Scan:

1. **Ribbons**: glowing hot pink and cyan ribbons of silk strands weaving through clear, cyan-edged glass polyhedra in a dark navy room above a glossy floor, the whole scene sliding right to left with depth parallax. The bass bends and widens the ribbons, each beat turns the glass a step, and the edges sparkle with the treble. It keeps a slow, dim drift in silence.
2. **Vortex**: a cyber tunnel of grid lines rushing past. Written by Alisan. The rings speed up and the field of view pulses with the bass, the spiral twists as it goes, and the whole thing fades out in silence.
3. **Silk Flight**: flying forward past a wide, glossy hot pink satin ribbon in a few broad folds that sweeps in from the edges and twists away into a teal dust cloud on near-black space, turning violet in the distance, with chunky cyan glass blocks tumbling past. The camera races when the music is loud, the bass widens the ribbon, every beat turns the glass and throws a burst of glitter, and the treble makes the specks and glass edges sparkle. It goes dim and still in silence.
4. **Flux**: an abstract light sweep. Huge fanned sheets of fine light strands, hot pink and molten gold, sweep in from the edges of the frame and swirl into a drifting vanishing point, like long-exposure light trails seen while flying. Gold flakes, soft bokeh and a few cyan glass shards streak out past the camera. Louder music flies faster, with longer streaks and more light, the beat is a soft swell, and the treble sparkles the glitter. Every motion glides. In silence it goes dim and still.
5. **Spectrum**: classic segmented LED spectrum bars.
6. **Tunnel**: fly through concentric rings of spectrum-reactive bars.
7. **Liquid**: Milkdrop-inspired psychedelic fluid that flows to the music.
8. **Kaleidoscope**: mirrored fractal folds that punch in on the bass.
9. **Neon Wave**: layered glowing green waveforms, shaped by the spectrum like an analogue sound analyser.
10. **Machine**: a port of the MIDEM Music Hack Day piece by [@mrdoob and @plamere](https://github.com/mrdoob/midemhackday), rebuilt from its source: twelve stations of lathe-turned cannons and drums (one per pitch class) and a ring of 40 pads. Each note onset fires balls that arc onto the drum and pad for that pitch and loudness; struck drums recoil and flash white. Smooth meshes, 4x MSAA with a depth buffer, and the original's camera path flown over the length of the track (Music/Spotify report it).
11. **Warp**: hyperspace star streaks.
12. **Constellation**: 4,000 bass-pumping particles around you.
13. **Nyan Cat**: pixel cat on a rainbow trail through the stars.
14. **Hamster Dance**: a scrolling wall of dancing hamsters. Drop your own animated GIFs (or APNG/PNG) into `~/Library/Application Support/Vibresia/Hamsters/` (**Visualizer → Open Hamster Folder…**) and they replace the drawn hamsters: tiled edge to edge at native pixels (integer-scaled), animating at their own frame timing and bouncing on the beat. Up to 16 images; the folder is re-checked every couple of seconds.
15. **Badger Badger**: rows of badgers dancing to the beat; big drops bring out the mushroom (or, every third, the snake).
16. **Whooping Llama**: dancing llamas in blankets, whooping on every beat.
17. **Dance Floor**: a Rubik's-cube floor in perspective. The camera pans, rolls and travels up and down the floor, all on the beat clock, and the tiles keep re-solving themselves. A fragment shader, themed by the active palette rather than being graded after the fact.
18. **The Band**: colour pixel-art musicians in ten genre sets (classical hall, DJ booth, rock theatre, pop studio, hip-hop street, jazz club, blues bar, country porch, R&B velvet, ambient), each with its own instruments and outfits. Apple's on-device sound classifier (SoundAnalysis), backed up by beat and bass detection, decides who walks on; the singer's voice (female, male or duet) comes from the vocal pitch. Playing follows the beat clock, with spectrum onsets as accents.

Vibscapes 1–5, 8–9, 11 and 13–18 are full-screen fragment shaders in `Render/FunShaders.swift`, drawn procedurally (no image assets). Vibscape 10 (`Machine`) is instanced 3D geometry in `Render/MachineRenderer.swift`.

Built with SwiftUI + OpenGL 3.3 + Core Audio process taps + Accelerate (vDSP).

## Running

The bundle is self-contained at `build/Vibresia.app`. To open it:

```
open build/Vibresia.app
```

Or to rebuild first:

```
./build-app.sh debug      # debug build at build/Vibresia.app
./build-app.sh release    # release build
```

Then click **Share System Audio** in the intro screen and pick the tab/app playing audio (Spotify, YouTube, etc.). macOS will ask for screen-recording permission — that's what gives us access to the audio.

Other sources:
- **Use Microphone** — visualizes whatever the mic hears.
- **Use Demo Tone** — synthesized kick + sweep, so you can see it work without sharing anything.

## Startup

Two optional switches, both **off until asked for** and both in the credits
popover (bottom right, "Made with ❤️"):

- **Start at login** — Vibresia opens by itself when you log in.
- **Open with Music or Spotify** — a small background watcher opens Vibresia
  when Apple Music or Spotify starts.

Both are ordinary user login items in `~/Library/LaunchAgents`:

```
com.minithlabs.visualiser.login          the app itself, at login
com.minithlabs.visualiser.music-watch     Contents/Helpers/VibresiaWatcher
```

Each plist points at a binary inside the app bundle, so it's rewritten on every
launch — the in-app updater replaces the bundle, and a plist that still pointed
at the old copy would launch nothing. That self-healing is the reason the
toggles can't silently rot.

Two deliberate choices worth knowing about:

- **Not `SMAppService`.** macOS's supported API refuses to register an app that
  isn't properly signed ("Operation not permitted" on every ad-hoc build), and
  a fallback to a hand-written plist would mean two mechanisms — and the
  possibility of the same item being registered twice. One plist, one switch.
- **Not listed in System Settings.** Login items registered this way don't
  appear under General → Login Items, so switch them off from the popover (or
  `Vibresia --login-off` / `--watch-off`).

The watcher sees only which apps launch — no window titles, no audio, no
playback state. From support, without a window to click in:

```
Vibresia --startup-status     # what both switches currently believe
Vibresia --login-on / --login-off
Vibresia --watch-on / --watch-off
~/Library/Logs/Vibresia/music-watch.log    # the watcher's own log
```

## A window that gets out of the way

The window goes down to 420×280 — small enough to sit in a corner while you
work. The chrome sheds pieces as it narrows, in the order least useful first:

| Width | What happens |
|---|---|
| ≥ 1100 | Everything: pills with labels, footer numbers, BPM |
| < 1100 | Footer numbers go (RMS, BASS, MID, TREB, BEAT). The vibscape stays — it's the one value someone watching wants |
| < 880 | Pills lose their labels and keep their glyph, swatch or dot. The menus underneath are unchanged |
| < 620 | The pills go entirely. The scene is the point at that size, and every choice is still a keystroke (1–0, `-`, `[`, `]`, `;`, `'`, `\`, `=`) or in the Visualizer menu |

The tier is decided in one place (`LayoutTier`) from the window's own resize
notifications, and `--ui-shot` renders the chrome at all four widths, so the
progression is reviewable in a PNG rather than by resizing a window and looking.

## Floating above other apps

**Float above other apps** (credits popover, or the Visualizer menu) puts the
window at `.floating`, so it stays above other apps' normal windows — handy when
you want the visualiser over your editor or a browser. Full-screen apps and the
menu bar still cover it, which is deliberate: anything higher would sit on top of
things you need to use.

The choice is remembered, and applied as soon as the window exists at launch.
The level is logged once whenever it changes (`[window] level = floating`), which
is the only way to answer "is it supposed to be on top?" from a bug report.

## First launch

A fresh install starts in **Auto Scan**, cycling every twenty seconds — with
so many vibscapes, nobody should have to guess that the good ones are behind a
menu, and a visualiser that sits on one scene forever looks like it missed
something. Pick a vibscape and that's remembered from then on; going back to Auto
Scan clears the memory, so "no choice" always means Auto Scan.

## Colour palettes

Five palettes, picked from the header. The palette is applied as a **post-process
over the finished frame** — a duotone grade that stretches the scene's
luminance ramp between a shadow and a highlight colour, then adjusts
saturation and lifts the blacks. Because it runs after the scene rather than
inside each shader, one palette themes *every* vibscape at once: the tunnel, the
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
default browser. No card details ever touch Vibresia.

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

**What is sent:** which vibscape you switched to, which palette, the coarse genre
the detector settled on, whether the support button got clicked, and crash
reports (what was on screen when it died, plus a stack trace — see below).

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

## Crash reports

Without this, a band-vibscape crash arrives as "it crashed sometimes" and a stack
trace from a friend three timezones away. So the app catches its own.

**On crash.** A handler on the fatal signals (and on uncaught Objective-C
exceptions) writes a report to
`~/Library/Application Support/Vibresia/Crashes/Vibresia-<stamp>-<id>.crash.json`,
then re-raises with the default disposition so macOS still writes its own `.ips`
into `~/Library/Logs/DiagnosticReports` exactly as before. Ours carries what the
system's can't: the vibscape and genre on screen, the band lineup, the audio source,
the last dozen actions, and a `backtrace()` of the faulting thread. The newest
20 reports are kept.

**Also straight to Discord.** If the build has a `ReportToken` (see the root
README), the report is posted to the site's `/api/notify` in the moment it
happens rather than waiting for the next launch — and it doesn't wait for the
analytics switch, because a crash is the report you can least afford to lose.
Audio failures (`audio_error`) and a source that couldn't be started
(`source_failure`) go the same way; a declined permission prompt doesn't,
because that's a choice rather than a fault.

**On next launch.** Each report is sent to PostHog as an `app_crashed` event —
vibscape, genre, reason, top 12 frames, last 12 breadcrumbs — and then deleted from
disk. Three uploads per launch, so a machine crashing in a loop doesn't spend a
minute talking about it.

**What goes in:** app state and stack traces. Nothing derived from what the user
is watching or listening to — no track names, no audio, no screen content, and
the machine's hostname stays local (the analytics line is "identifies an install,
not a person").

**The switch.** Uploads ride on the same "Share anonymous usage" toggle as
everything else, because a crash report is usage data by another name. Reports
stay on disk either way, and **Vibresia → Report a Problem…** emails the latest
one to you as a readable summary plus the JSON attachment — user-initiated, so it
works with the toggle off. **Reveal Crash Reports…** opens the folder.

`--simulate-crash` faults on purpose three seconds in, so the whole
report-and-upload path can be checked without waiting for a real one:

```
open build/Vibresia.app --args --simulate-crash   # writes a report
open build/Vibresia.app                            # uploads it, deletes it
```

## Header controls

Everything lives in the top bar so the visualiser gets the whole window:

- **Vibscape picker** (left of the group) — every vibscape in a drop-down. Each
  row shows its number-row shortcut, so the keyboard route stays discoverable
  now that the list isn't permanently on screen.
- **Genre picker** — only in band vibscape (or when Auto Scan is sitting on the
  band), since the genre drives the stage, the lineup and the palette there.
  Clicking a genre locks it for the current song; the next song re-arms auto.
  The confidence bar next to the name shows how sure the detector is.
- **Palette picker** — the five colour palettes, each with its own swatch.
- **Source pill** and **BPM** readout.

Click away from an open list to dismiss it.

## Custom vibscapes, and the local MCP server

A vibscape is a fragment shader: one function, `vec3 render(vec2 p, float t)`,
that returns a colour. The app supplies the uniforms (`uBass`, `uBands`,
`uBeats`, …), the helpers and `main()`; the vibscape supplies the picture.

There are three ways to write one, and the app offers all three in
**View All → + Custom Vibscape**: paste code you already have, ask an AI
assistant to write it (a prompt is provided), or open a file somebody sent
you. Nothing is saved until it compiles — **Test** draws the vibscape and shows
you the picture, and a failure is explained in words rather than in the
graphics driver's log.

### The MCP server

Vibresia also ships a local [MCP](https://modelcontextprotocol.io) server,
so an agent can write a vibscape, check it compiles, look at the result and try
again — without anybody copying code by hand.

Point an agent at it with:

```bash
claude mcp add vibresia -- "/Applications/Vibresia.app/Contents/MacOS/Vibresia" --mcp
```

The path has to be wherever the app actually is. The Custom Vibscape sheet shows
the right command for the copy on the machine, with a button to copy it.

For clients that read a JSON file rather than a command line:

```json
{
  "mcpServers": {
    "vibresia": {
      "command": "/Applications/Vibresia.app/Contents/MacOS/Vibresia",
      "args": ["--mcp"]
    }
  }
}
```

It's the same binary, run with `--mcp`: it speaks JSON-RPC over stdin and
stdout, has no window, no dock icon and no analytics, and doesn't listen on
a port — so there's nothing to secure. It reads and writes the same files
the app does, so a vibscape an agent writes turns up in the app within a
second, whether or not Vibresia is open.

The tools it offers:

| Tool | What it does |
| --- | --- |
| `list_vibscapes` | Every vibscape: the ones that ship with the app and the user's own. |
| `get_vibscape` | The full source of one of the user's own vibscapes. |
| `vibscape_reference` | The uniforms and helpers available, and a worked example. |
| `test_vibscape` | Compile a shader and draw it, without saving anything. |
| `create_vibscape` | Save a new vibscape. Compiles first; won't save code that doesn't run. |
| `update_vibscape` | Change one of the user's own vibscapes. Compiles first. |
| `delete_vibscape` | Remove one of the user's own vibscapes. |

`test_vibscape` returns the picture as well as the verdict, so an agent can see
what it made rather than being told it compiled.

## Keyboard shortcuts

- `1`–`9`, `0`, `-`, `[`, `]`, `;`, `'`, `\` — switch vibscape. The keys follow the order of the vibscape list, so rearranging the list in View All rearranges the shortcuts.
- `Space` / `Esc` — toggle the intro overlay

## Development flags

- `--vibscape <name>` — start in a given vibscape (e.g. `--vibscape machine`)
- `--palette N` — start with a given colour palette (0–4)
- `--autoscan` — start in auto scan
- `--scan-seconds N` — shorten the auto-scan dwell time (default 20s)
- `--about` — open the credits popover on launch (checks the Stripe embed)
- `--share` — with `--about`, opens the share sheet without a click
- `--snapshot` — render one frame of every vibscape to PNG and exit
- `--snapshot --genres` — render one frame of every genre and exit
- `--ui-shot` — render the SwiftUI chrome to PNG (the OpenGL layer won't appear)
- `--record <dir>` — capture consecutive frames of the GL output
- `--simulate-crash` — crash on purpose after 3s, to exercise the crash reporter
- `--startup-status` — print whether the login item and music watcher are on
- `--login-on` / `--login-off` — toggle "start at login" and exit
- `--watch-on` / `--watch-off` — toggle "open with Music or Spotify" and exit
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

- `1`–`9`, `0`, `-`, `[`, `]`, `;`, `'`, `\` — switch vibscape. The keys follow the order of the vibscape list, so rearranging it in View All rearranges the shortcuts: the first vibscape in the list is `1`, the second `2`, and so on. With the shipped order that makes `0` Machine, `-` Warp, `[` Constellation, `]` Nyan Cat, `;` Hamster Dance, `'` Badger Badger, `\` Whooping Llama, `,` Dance Floor, `.` The Band.
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
SNAPSHOT_DIR=/tmp/viz_snapshots ./build/Vibresia.app/Contents/MacOS/Vibresia --snapshot
```

This renders one frame of each vibscape to PNG and exits.