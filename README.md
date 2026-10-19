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
| `site/analytics.js` | Anonymous page-view / click tracking for the landing page. |
| `worker/index.js` | Cloudflare Worker: serves `./site` and handles `/download` (redirect + Discord notification). |
| `site/sitemap.xml`, `site/robots.txt` | What Google is pointed at. One URL; the plain-text agent pages are deliberately left crawlable but unlisted. |
| `site/_headers`, `site/_redirects` | Cloudflare response headers (caching, security) and canonical-path redirects. |
| `scripts/check-modes.sh` | Fails if a visualiser mode is missing from the landing page, or the version in its structured data is stale. |
| `scripts/check-posthog.sh` | Fails if the site and the app report to different PostHog projects. |
| `scripts/check-no-webhook-leak.sh` | Fails if a Discord webhook URL is anywhere in the tree. |
| `wrangler.toml` | Deploys the Worker (and `site/` through it) to Cloudflare. |

## Developing

```bash
cd VisualiserMac
./build-app.sh debug      # build/AudioVane.app
open build/AudioVane.app
```

## Landing page analytics

`site/analytics.js` is a ~180-line PostHog client — no SDK, no session replay,
no cookies — reporting into the same PostHog project as the app, separated by a
`surface` property (`web` vs `mac_app`).

Events: `page_view`, `demo_played`, `mode_card_viewed` (which mode cards got
scrolled to), `download_clicked`, `install_command_copied` (`ask-ai` or `curl` —
the interesting split, since they are different audiences), `coffee_clicked`
(by placement) and `outbound_clicked`.

To see them without touching production, point the meta tag at a local sink:

```bash
python3 - <<'PY'
p='site/index.html'; s=open(p).read()
open(p,'w').write(s.replace('https://us.i.posthog.com">','http://127.0.0.1:8099">'))
PY
(cd site && python3 -m http.server 8098)   # then open http://127.0.0.1:8098
```

The footer has a one-click opt-out, and Do Not Track is honoured: both stop the
page sending anything at all.

## Download notifications (Discord)

Every download goes through `/download` on the Worker, which 302s to the latest
GitHub release and posts an embed to Discord. Server-side rather than from the
page, for two reasons: a webhook URL in the HTML would be public, and a click
that never completes isn't a download.

The embed carries source, city/country (from Cloudflare's geo), referrer,
browser, and whether that browser has downloaded before.

```bash
npx wrangler secret put DISCORD_WEBHOOK_URL     # once; the webhook URL in Discord
npx wrangler deploy
curl https://audiovane.minithlabs.com/api/health   # {"discord":"configured"}
```

Locally, `.dev.vars` (gitignored) points the webhook at a stub:

```bash
npx wrangler dev --port 8787
curl -s 'http://127.0.0.1:8787/download?src=hero&seen=0' -A 'Mozilla/5.0'
npm test                                        # 13 tests, no network
```

Notes:

- **The webhook URL is a credential.** `scripts/check-no-webhook-leak.sh` fails
  if one appears in the tree — delphina had the same problem and it ended up
  baked into dozens of release tags. If it ever leaks, recreate the webhook in
  Discord and put the new one back with `wrangler secret put`.
- Bots and link previewers are filtered out, a double-clicked button only posts
  once (5s debounce, 30/hour), and the post goes out via `ctx.waitUntil` with a
  timeout and one retry — so Discord being down can't slow down or break a
  download.
- Switch it off by setting `DISCORD_NOTIFICATIONS_ENABLED` to `"false"` in
  `wrangler.toml` and redeploying; the site keeps working either way.
- `install.sh` still downloads straight from GitHub, so script installs don't
  produce notifications.

## SEO

- **Submit the sitemap** once in [Search Console](https://search.google.com/search-console/sitemaps/submit) — `https://audiovane.minithlabs.com/sitemap.xml`. Re-submit after site deploys; it also carries `lastmod`.
- **Structured data** is `SoftwareApplication` + `Organization` JSON-LD in `index.html`. Bump `softwareVersion` with `VisualiserMac/VERSION` — `scripts/check-modes.sh` fails the release if you forget.
- **Turn on "Always Use HTTPS"** in the Cloudflare zone for `minithlabs.com`. As of the last audit, `http://audiovane.minithlabs.com/` served a 200 instead of redirecting; `site/_redirects` covers the same ground but the zone setting is the real fix.
- **Caching** is Cloudflare's default (`max-age=0, must-revalidate`), and a `Cache-Control` rule in `site/_headers` *appends* to that rather than replacing it, so it can't be changed that way. Repeat visits revalidate with a 304 from the ETag instead of re-downloading 5.9MB, which is the part that matters.
- Page is a single static file: one H1, 13 lazy-loaded images with descriptive alt text, no framework. Keep it that way — LCP measured ~0.08s locally and CLS ~0.005 before any of this.

## Tuning The Band

`VisualiserMac/Tests/band-fixtures.yaml` lists YouTube videos labelled with their genre and who's playing. `scripts/band-eval.py` plays each one in Chrome while AudioVane listens, then prints a scorecard (genre right? right musicians on stage?) and saves the detector's features and per-genre scores to `VisualiserMac/Tests/eval-results/` for tuning. AudioVane needs system audio permission first; keep other audio off while it runs.

```bash
scripts/band-eval.py --check     # validate the fixtures file
scripts/band-eval.py             # run them all (about a minute each)
scripts/band-eval.py --only jazz
```

## Releasing

1. Bump `VisualiserMac/VERSION`.
2. Add any new mode to `site/index.html` (a card with `data-mode="<case name>"`) and update the JSON-LD `softwareVersion`.
3. `VisualiserMac/release.sh` runs both site checks, builds, zips `AudioVane.app` and publishes GitHub release `v<VERSION>`. The installer and the app's update check always use the latest release.
4. `npx wrangler deploy` if the site or worker changed, then re-submit the sitemap. First deploy after cloning needs `npx wrangler secret put DISCORD_WEBHOOK_URL` (see [Download notifications](#download-notifications-discord)).
