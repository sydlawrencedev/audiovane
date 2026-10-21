# Vibresia

A free macOS app for visual worlds that move with your music. It listens to whatever your Mac is playing and turns it into live scenes, from neon waveforms to a pixel-art band that walks on stage when it hears their instrument — and you can write a world of your own, or have an AI assistant write it for you.

**Website & install:** https://vibresia.com

```bash
curl -fsSL https://vibresia.com/install.sh | bash
```

Or ask an AI assistant: *"install vibresia from https://vibresia.com"*.

If you enjoy it, you can [buy me a coffee](https://buy.stripe.com/7sY3cuekN6z66L1c0cbEA01).

Found a bug or have an idea? [File an issue](https://github.com/sydlawrencedev/vibresia/issues). Pull requests are very welcome, especially new vibescapes: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Repository layout

| Path | What |
|---|---|
| `VisualiserMac/` | The macOS app (Swift, SwiftUI, OpenGL). See its [README](VisualiserMac/README.md). |
| `site/` | The landing page, installer (`install.sh`) and AI install instructions (`install.md`, `llms.txt`). |
| `site/analytics.js` | Anonymous page-view / click tracking for the landing page. |
| `site/github.js` | Changelog and open issues, fetched from the GitHub API when scrolled into view. |
| `worker/index.js` | Cloudflare Worker: serves `./site` and handles `/download` (redirect + Discord notification). |
| `site/sitemap.xml`, `site/robots.txt` | What Google is pointed at. One URL; the plain-text agent pages are deliberately left crawlable but unlisted. |
| `site/_headers`, `site/_redirects` | Cloudflare response headers (caching, security) and canonical-path redirects. |
| `scripts/check-vibescapes.sh` | Fails if a vibescape is missing from the landing page, or the version in its structured data is stale. |
| `scripts/check-posthog.sh` | Fails if the site and the app report to different PostHog projects. |
| `scripts/check-no-webhook-leak.sh` | Fails if a Discord webhook URL is anywhere in the tree. |
| `wrangler.toml` | Deploys the Worker (and `site/` through it) to Cloudflare. |

## Developing

```bash
cd VisualiserMac
./build-app.sh debug      # build/Vibresia.app
open build/Vibresia.app
```

### Custom vibescapes and the local MCP server

A vibescape is a fragment shader — one function, `vec3 render(vec2 p, float t)` —
and the app supplies the uniforms, the helpers and everything else.

Vibresia ships a local [MCP](https://modelcontextprotocol.io) server, so an AI
agent can write a vibescape, check it compiles, look at the picture and try again
without anybody copying code by hand:

```bash
claude mcp add vibresia -- "/Applications/Vibresia.app/Contents/MacOS/Vibresia" --mcp
```

It's the same binary run with `--mcp`, speaking JSON-RPC over stdin — no
window, no port, no analytics. It reads and writes the same files the app
does, so a vibescape an agent writes shows up in the app within a second. See
[VisualiserMac/README.md](VisualiserMac/README.md#custom-vibescapes-and-the-local-mcp-server)
for the tools it offers.

### Version numbers

The build version is the date it was built, so there's no number to bump:

```
MAJOR.MINOR.PATCH
```

`MAJOR` counts years since 2026, `MINOR` is the month, and `PATCH` is the day of the month followed by the build number of that day — `0.10.201` is the 20th of October 2026, the first build of that day.

`VisualiserMac/version.sh` computes it, and `build-app.sh` bakes it into the app. `release.sh` records it in `VisualiserMac/VERSION` and the landing page before tagging the release, so the app, the site and the git tag always agree.

## Landing page analytics

`site/analytics.js` is a ~180-line PostHog client — no SDK, no session replay,
no cookies — reporting into the same PostHog project as the app, separated by a
`surface` property (`web` vs `mac_app`).

Events: `page_view`, `demo_played`, `vibescape_card_viewed` (which vibescape cards got
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
curl https://vibresia.com/api/health   # {"discord":"configured"}
```

**Errors from the app.** The app can't hold the webhook (it's in the app
bundle, where anyone can read it), so it posts to `POST /api/notify` on this
site and the Worker forwards it. Set the shared token as a second secret, then
bake the same value into the app:

```bash
npx wrangler secret put NOTIFY_TOKEN          # any random string
REPORT_TOKEN=<the same string> ./build-app.sh release
```

Three things arrive: `audio_error` (the audio source failed or was cut off —
the failure a stack trace will never show you), `source_failure` and
`app_crash` (with the top frames). A denied permission prompt is a choice, not
a fault, so it isn't reported.

Unlike usage analytics, this is **not** behind the in-app toggle: a crash is
the report you can least afford to lose, and the user asked for that source
explicitly. What's sent is app state — vibescape, genre, error text — never audio or
track names. Errors get their own cooldown (one a minute, 60/hour) so a broken
install can't flood the channel, and `DISCORD_ERRORS_ENABLED = "false"` turns
them off without touching download alerts.

Locally, `.dev.vars` (gitignored) points the webhook at a stub:

```bash
npx wrangler dev --port 8787
curl -s 'http://127.0.0.1:8787/download?src=hero&seen=0' -A 'Mozilla/5.0'
npm test                                        # 13 tests, no network
```

Notes:

- **The webhook URL and the notify token are both credentials.**
  `scripts/check-no-webhook-leak.sh` fails if either appears in the tree — delphina had the same problem and it ended up
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

## Changelog and open issues

Both sections on the landing page read from `api.github.com` at runtime rather
than being baked in, so they can't go stale between deploys. Three things keep
that honest:

- **Cached** in `sessionStorage` for 15 minutes. GitHub's unauthenticated API
  allows 60 requests an hour *per IP*, and every visitor would be spending from
  the same one.
- **Lazy** — the fetch starts when the section scrolls into view.
- **Never fatal** — if GitHub is down, rate-limiting us, or the JSON moves, the
  section says so and leaves a link to the repo behind. Issue titles are
  rendered through `textContent`, never `innerHTML`, because they're whatever
  someone typed into a text box.

## SEO

- **Submit the sitemap** once in [Search Console](https://search.google.com/search-console/sitemaps/submit) — `https://vibresia.com/sitemap.xml`. Re-submit after site deploys; it also carries `lastmod`.
- **Structured data** is `SoftwareApplication` + `Organization` JSON-LD in `index.html`. The version is the build's date, so there's nothing to bump by hand — `VisualiserMac/version.sh --write` puts it in both `index.html` and `VisualiserMac/VERSION`, and `scripts/check-vibescapes.sh` fails the release if they drift apart.
- **Turn on "Always Use HTTPS"** in the Cloudflare zone for `vibresia.com`. The Worker's own `http:` → `https:` redirect covers the same ground, but the zone setting is what stops a duplicate being served at all. The old `audiovane.minithlabs.com` name is still attached to the Worker so it can redirect — see the note below.
- **The old domain is a redirect, not a second site.** `audiovane.minithlabs.com` is attached to the same Worker, which answers it with a 301 to `vibresia.com` keeping the path — so the old install command and any old link still work. Its DNS has to keep pointing at Cloudflare for that to happen. One thing a domain change can't carry over: the analytics opt-out is in the browser's `localStorage`, which is per-origin, so anyone who opted out of analytics on the old site has to do it again on the new one.
- **The Worker is attached with routes, not custom domains.** `vibresia.com` was pointed at Cloudflare before the Worker existed, so its DNS records are ones Cloudflare didn't make; a custom domain would want to own them and refuses to overwrite them. A route binds the hostname to the Worker and leaves the DNS alone. `run_worker_first` is on for the same reason: the redirects are decided in the Worker, and an asset served straight from the edge would skip them.
- **Caching** is Cloudflare's default (`max-age=0, must-revalidate`), and a `Cache-Control` rule in `site/_headers` *appends* to that rather than replacing it, so it can't be changed that way. Repeat visits revalidate with a 304 from the ETag instead of re-downloading 5.9MB, which is the part that matters.
- Page is a single static file: one H1, 16 lazy-loaded images with descriptive alt text, no framework. Keep it that way — LCP measured ~0.08s locally and CLS ~0.005 before any of this.

## Tuning The Band

`VisualiserMac/Tests/band-fixtures.yaml` lists YouTube videos labelled with their genre and who's playing. `scripts/band-eval.py` plays each one in Chrome while Vibresia listens, then prints a scorecard (genre right? right musicians on stage?) and saves the detector's features and per-genre scores to `VisualiserMac/Tests/eval-results/` for tuning. Vibresia needs system audio permission first; keep other audio off while it runs.

```bash
scripts/band-eval.py --check     # validate the fixtures file
scripts/band-eval.py             # run them all (about a minute each)
scripts/band-eval.py --only jazz
```

## Releasing

1. Add any new vibescape to `site/index.html` (a card with `data-vibescape="<case name>"`).
2. `VisualiserMac/release.sh` runs both site checks, decides the version from the date, records it in `VisualiserMac/VERSION` and the landing page, builds, zips `Vibresia.app` and publishes GitHub release `v<VERSION>`. The installer and the app's update check always use the latest release.
3. `npx wrangler deploy` if the site or worker changed, then re-submit the sitemap. First deploy after cloning needs `npx wrangler secret put DISCORD_WEBHOOK_URL` (see [Download notifications](#download-notifications-discord)).
