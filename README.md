# AudioVane

A free music visualiser for macOS. It listens to whatever your Mac is playing and turns it into live visuals: thirteen modes, from neon waveforms to a pixel-art band that walks on stage when it hears their instrument.

**Website & install:** https://audiovane.minithlabs.com

```bash
curl -fsSL https://audiovane.minithlabs.com/install.sh | bash
```

Or ask an AI assistant: *"install audiovane from https://audiovane.minithlabs.com"*.

If you enjoy it, you can [buy me a coffee](https://buy.stripe.com/fZu14mb8B9Li9Xd5BObEA00).

Found a bug or have an idea? [File an issue](https://github.com/sydlawrencedev/audiovane/issues). Pull requests are very welcome, especially new visualisations: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Repository layout

| Path | What |
|---|---|
| `VisualiserMac/` | The macOS app (Swift, SwiftUI, OpenGL). See its [README](VisualiserMac/README.md). |
| `site/` | The landing page, installer (`install.sh`) and AI install instructions (`install.md`, `llms.txt`). |
| `scripts/check-modes.sh` | Fails if a visualiser mode is missing from the landing page. |
| `wrangler.toml` | Deploys `site/` to Cloudflare. |

## Developing

```bash
cd VisualiserMac
./build-app.sh debug      # build/AudioVane.app
open build/AudioVane.app
```

## Releasing

1. Bump `VisualiserMac/VERSION`.
2. Add any new mode to `site/index.html` (a card with `data-mode="<case name>"`).
3. `VisualiserMac/release.sh` builds, zips `AudioVane.app` and publishes GitHub release `v<VERSION>`. The installer and the app's update check always use the latest release.
4. `npx wrangler deploy` if the site changed.
