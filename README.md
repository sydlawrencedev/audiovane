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
| `worker/share.test.js` | Tests for the shared-vibescape endpoints. |
| `migrations/` | D1 schema — one table, one row per shared vibescape. |
| `site/sitemap.xml`, `site/robots.txt` | What Google is pointed at. One URL; the plain-text agent pages are deliberately left crawlable but unlisted. |
| `site/_headers`, `site/_redirects` | Cloudflare response headers (caching, security) and canonical-path redirects. |
| `scripts/check-vibescapes.sh` | Fails if a vibescape is missing from the landing page, or the version in its structured data is stale. |
| `scripts/check-posthog.sh` | Fails if the site and the app report to different PostHog projects. |
| `scripts/check-no-webhook-leak.sh` | Fails if a Discord webhook URL, a notify token or a share token is anywhere in the tree. |
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

## Shared vibescapes

A custom vibescape — one somebody wrote — used to travel as its payload in
the link: `vibresia.com/share/?d=<base64 of the deflated shader>`. That
works with no backend at all, which is why it was built that way. But the
link was around 370 characters, and the server answered it with a 307 to
add the trailing slash, which WhatsApp's link-preview crawler did not
follow — so the preview was blank and the link looked broken in a chat.

Now the payload is stored and the link is short:

```
POST /api/share   {payload, name, author, image, key}   →  {"url": "https://vibresia.com/s/k3f9x2"}
GET  /s/k3f9x2                                         the share page, with the payload inlined
GET  /og/k3f9x2.jpg                                    a picture of this vibescape
```

- **The same vibescape always gets the same link.** A share used to be made
  fresh every time — a new row, a new id, a new URL — so sharing the same
  vibescape twice gave you two links, and re-sharing one somebody sent you
  gave you a third. The app hashes the vibescape's contents (name, author,
  url, shader) and sends the hash; the Worker looks for a share with that
  hash, and for one with the same payload, and returns the row it finds
  rather than making another. The `key` column has a partial unique index
  on it, so two devices sharing at once land on one row.
- **A vibescape that arrived on a link keeps the link it arrived on.** The
  page puts the share's id in the deep link, the app remembers it with the
  vibescape, and sharing it on hands that link back: the person who sent it
  to you sent you that link, and the person you send it to should get the
  same one. Edit the vibescape and the hash changes, so it gets a link of
  its own.
- **The picture says who made it.** The app stamps the Vibresia mark and the
  credit onto the picture it uploads, and the built-in pictures on the site
  are drawn by the same code — see `VisualiserMac/Sources/VibresiaBrand`.

## The gallery

`vibresia.com/vibescapes` lists the shares that were ticked into it.

Sharing a vibescape has always made a link anybody can open. The gallery is
different: it lists them, so anything in it is findable by anybody at all —
and the name and the author on it are public. The share sheet says so, and
has a tickbox, on by default.

- **The app asks.** `POST /api/share` takes `public`, and the share sheet
  has a tickbox next to the name.
- **The Worker stores it** in an `is_public` column and serves the list at
  `/vibescapes` (the page) and `/api/gallery` (the same thing as JSON). The
  cards are built on the server, so the page works with no JavaScript and a
  crawler sees the list.
- **The shares that were made before the gallery existed are not in it.**
  They were never offered the choice, and publishing them without asking
  would put somebody else's name on the front page of the site. Sharing one
  again with the tickbox on puts it in.

- **D1, not Workers KV.** KV is eventually consistent — a link opened ten
  seconds after it was shared could reach an edge that hadn't seen the write
  and 404, which is the feature failing at exactly the moment it is used.
  D1 is SQLite-backed and strongly consistent, so the link works the moment
  it exists. It is free: 100,000 rows written a day, 5,000,000 read, 5 GB
  stored. A share is a row with a payload and a ~120 KB picture in it.
- **The page is served, not redirected to.** A redirect is what the preview
  crawler was not following. The Worker fetches `/share/` and rewrites the
  parts that are specific to the share: the title, the description, and the
  `og:image` that points at the stored picture. Crawlers do not run the
  page's JavaScript, so that has to be right in the HTML itself.
- **The picture is the vibescape.** The app renders it at 1200x630, at the
  same moment the share page draws its still (six seconds in, so anything
  driven by time has reached its stride), so the preview in a chat is the
  picture the recipient gets.
- **The long link still works.** It carries the payload with it, so it
  needs nothing stored. The app falls back to it if the site can't be
  reached — sharing is not allowed to depend on the network.

The endpoint needs a token, which is a speed bump rather than a lock: it
ships inside the app, so anyone can read it out of the bundle. What it
stops is a script creating shares to burn the daily write quota.

```bash
npx wrangler secret put SHARE_TOKEN        # once; the same value goes in VisualiserMac/.env
npx wrangler d1 migrations apply vibresia-shares --remote
node scripts/backfill-share-payload-hashes.mjs
```

**The order matters.** The migration adds the columns the Worker looks shares
up by, and the backfill fills in the hashes for the shares that were made
before the columns existed. Run the migration first, then the backfill, then
deploy the Worker. The Worker survives a database that hasn't been migrated
— it falls back to storing every share on its own, which is what it used to
do — but the same-link behaviour needs the new columns.

`SHARE_TOKEN` is a credential in the same class as `NOTIFY_TOKEN`, so
`scripts/check-no-webhook-leak.sh` fails if it ends up in the tree.

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

## Exporting a video

The share sheet can save the last ten seconds of a vibescape, with the music,
as a movie in Downloads.

The picture is the app's own renderer — the same draw the window is doing,
over the last ten seconds of its clock — so it is the vibescape rather than
a picture of it. The sound is the last ten seconds of what the app was
hearing, which is the music as it was.

The clip is as long as the audio the app has: ten seconds of music if there
has been ten seconds of music, and what there is if there hasn't. The app
has to be listening to something for there to be any.

```bash
./build/Vibresia.app/Contents/MacOS/Vibresia --export-video band /tmp/out.mp4
```

## The song, and its genre

The Band's genre comes from the song when the app can work out what is
playing. Two ways, and they sit side by side:

- **By name.** Apple Music and Spotify both post a notification when the
  track changes, with the title and the artist in it. The app looks the song
  up in Apple's public catalogue, which knows its genre — so the stage is
  chosen for the track rather than guessed at from the waveform.
  `VisualiserMac/Sources/VisualiserMac/Audio/SongIdentifier.swift`.
- **By listening.** ShazamKit matches a signature of the sound against
  Shazam's catalogue, which works with anything that makes a sound — a
  browser, a film — rather than only with the players that post
  notifications. `VisualiserMac/Sources/VisualiserMac/Audio/ShazamIdentifier.swift`.

The first one is what ships. The second one is behind a flag, because
matching against Shazam's catalogue needs the app to be *allowed* to ask,
and being allowed is decided by the ShazamKit service on the app's identifier
in the developer portal.

### What ShazamKit needs, and why it isn't on by default

Apple issues the `com.apple.developer.shazamkit` entitlement for apps signed
with a provisioning profile. This app is signed with a Developer ID
certificate and notarized, so the entitlement has to be declared in the
signature by hand — and declaring one the team hasn't been granted is not a
build that fails to match, it is a build that will not launch. macOS kills
the process:

```
$ SHAZAMKIT=1 ./build-app.sh debug && ./build/Vibresia.app/Contents/MacOS/Vibresia
Killed (exit 137)
```

The same app without the entitlement runs, and the match comes back
`com.apple.ShazamCore error 102` — "not allowed", not "not found".

So the entitlement is opt-in (`SHAZAMKIT=1`) and only worth turning on once
the ShazamKit service is enabled for `com.minithlabs.visualiser` in the
developer portal *and* Apple grants it for a Developer ID signature.

The spike is still here, because that question deserves an answer rather
than a forum post:

```bash
./build/Vibresia.app/Contents/MacOS/Vibresia --shazam-spike
```

### What leaves the machine

The audio never does — it is analysed locally and drawn locally, and the
band's stage is drawn from what the shader does with it.

The *name* of the song does, when a music app says what it is playing: the
title and the artist are looked up in Apple's public catalogue, which is the
same search the iTunes Store does. Nothing else is sent, and no account is
involved. The catalogue's answer is a genre, and the genre is a local
decision from then on.

The lookup needs both the title and the artist to match. The catalogue will
happily answer "Me and Your Mama" for "Redbone" — same artist, different
song — and a wrong song means a wrong genre on the stage, so a result that
isn't clearly the right song is thrown away rather than used. When the
catalogue doesn't know the song, the app falls back to the audio heuristic
it has always used, and nothing is lost.

To try the lookup without a music app in the picture:

```bash
./build/Vibresia.app/Contents/MacOS/Vibresia --song-lookup "bad guy" "Billie Eilish"
```

## Tuning The Band

`VisualiserMac/Tests/band-fixtures.yaml` lists YouTube videos labelled with their genre and who's playing. `scripts/band-eval.py` plays each one in Chrome while Vibresia listens, then prints a scorecard (genre right? right musicians on stage?) and saves the detector's features and per-genre scores to `VisualiserMac/Tests/eval-results/` for tuning. Vibresia needs system audio permission first; keep other audio off while it runs.

```bash
scripts/band-eval.py --check     # validate the fixtures file
scripts/band-eval.py             # run them all (about a minute each)
scripts/band-eval.py --only jazz
```

## Releasing

1. Add any new vibescape to `site/index.html` (a card with `data-vibescape="<case name>"`).
2. `VisualiserMac/release.sh` runs both site checks, decides the version from the date, records it in `VisualiserMac/VERSION` and the landing page, builds, zips `Vibresia.app` and publishes GitHub release `v<VERSION>`. The installer and the app's update check always use the latest release. If a Developer ID certificate is in the keychain, the release is notarized as part of this — the ticket is stapled onto the app between the build and the zip, because signing the bundle again would invalidate it. See [Signing and notarization](VisualiserMac/README.md#signing-and-notarization).
3. `npx wrangler deploy` if the site or worker changed, then re-submit the sitemap. First deploy after cloning needs `npx wrangler secret put DISCORD_WEBHOOK_URL` (see [Download notifications](#download-notifications-discord)).
