# Contributing to AudioVane

Thanks for helping! Bug reports, ideas and pull requests are all welcome, and **new visualisations are especially welcome**.

- **Bugs and ideas:** [open an issue](https://github.com/sydlawrencedev/audiovane/issues). For bugs, include your macOS version, the mode you were in and what was playing.
- **Pull requests:** fork, branch, and open a PR against `main`. Small, focused PRs are easiest to review. Screenshots or a short screen recording help a lot for anything visual.

## Building

You need macOS 14.2+ and the Swift toolchain (Xcode or the command-line tools).

```bash
cd VisualiserMac
./build-app.sh debug
open build/AudioVane.app
```

Pick **Use Demo Tone** on the intro screen to test without sharing system audio.

## Adding a visualisation

Most modes are a single full-screen fragment shader, which is the quickest way in.

1. **Register the mode** in `VisualiserMac/Sources/VisualiserMac/AppState.swift`: add a `case` to `VisualizerMode` (above `autoScan`, which must stay last) and a `displayName`. Give it an SF Symbol in `UI/ModePicker.swift` (`symbolName`).
2. **Write the shader** in `Render/FunShaders.swift`: add a `static let yourMode = """ … """` with a `main()` that writes `fragColor`, and add `(.yourMode, yourMode)` to `FunShaders.modes`. The shared `prelude` at the top of that file gives you:
   - `uTime`: animation clock (stops when the music does)
   - `uBass`, `uMid`, `uTreble`, `uLevel`: smoothed energy, 0 to 1
   - `uBands[96]`: the spectrum, 40Hz–16kHz on a log scale (`bandAt(x)` reads it with x from 0 to 1)
   - `uBeat`, `uBeatStrength`: a beat this frame, and a decaying pulse
   - `uBeats`: a beat counter locked to the detected tempo (`fract(uBeats)` is the phase within a beat). It's continuous: the renderer eases each beat's phase correction in over ~0.4 s, so it never steps or runs backwards
   - `uScroll`: forward-only distance that moves faster when louder
   - `uActive`: 0 in silence, easing to 1 with sound
   - `uLevelSmooth`, `uBassSmooth`: slow versions of `uLevel` and `uBass` (rise over ~0.3 s, fall over ~1.5 s). Use them for swells, brightness and size that should breathe with the music rather than flicker
   - `uPresence`: music presence, 0 in silence and 1 with music, easing in and out over ~2.3 s with no chatter at quiet passages. Use it to morph between an idle state and the playing look
   - `uClock`: wall-clock seconds that keep running in silence. Only for a mode that should never stop completely (Ribbons keeps a slow drift); everything else follows the house rule below
   - helpers: `screenP()`, `sdCircle`, `sdBox`, `sdSeg`, `fill`, `rot`, `hash21`, …
3. **Follow the house rules:**
   - In silence the mode should be still: scale motion and colour by `uActive`, and drive time from `uTime`, `uBeats` or `uScroll`.
   - Never multiply time by a value that goes up and down, or things jump backwards. Use `uScroll` for "faster when louder".
   - Draw everything procedurally (no image assets), and don't copy anyone else's artwork.
4. **Check it renders:**
   ```bash
   ./build-app.sh debug
   SNAPSHOT_DIR=/tmp/av ./build/AudioVane.app/Contents/MacOS/AudioVane --snapshot
   ```
   This writes a PNG of every mode to `/tmp/av` and logs any shader compile errors. To watch it live: `./build/AudioVane.app/Contents/MacOS/AudioVane --mode yourMode`.
5. **Add it to the website:** in `site/index.html`, add a card to the modes grid with `data-mode="yourMode"` (the `case` name) and a 640×360 thumbnail in `site/media/modes/`. `scripts/check-modes.sh` fails until every mode has a card, and releases run it.

Modes that need more than a shader (3D geometry, per-frame state) live in their own renderer. See `Render/MachineMode.swift` and `Render/MachineRenderer.swift` for an example.

## Releases

Maintainers release with `VisualiserMac/release.sh` after bumping `VisualiserMac/VERSION`; see the [README](README.md#releasing).
