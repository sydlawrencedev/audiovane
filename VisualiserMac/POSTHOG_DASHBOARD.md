# PostHog dashboard — Vibresia

Everything here is copy-paste. Project **673583**.

## One-time setup

1. **Settings → Project settings → Project API Key** — copy the `phc_…` key.
   Put it in `VisualiserMac/.env`:
   ```
   POSTHOG_KEY=phc_xxxxxxxxxxxxxxxxxxxx
   POSTHOG_HOST=https://eu.i.posthog.com   # or https://us.i.posthog.com
   ```
   The numeric project ID is *not* the key — the capture endpoint authenticates
   with the `phc_` key only.

2. **Settings → Data management → Set person properties.** Create these as
   numeric properties so the breakdowns work:

   | Property | Type | Note |
   |---|---|---|
   | `surface` | string | `mac_app` for the app, `web` for the landing page. **Filter on this** in any insight that mixes the two. |
   | `app_version` | string | matches `CFBundleShortVersionString` |
   | `arch` | string | `arm64` / `x86_64` |
   | `os_version` | string | e.g. `Version 26.6.2 (Build 25G83)` |
   | `locale` | string | e.g. `en_GB` |

   In **Settings → Data management → Properties → Filter properties** leave
   `distinct_id` and `session_id` alone.

3. Turn off person profiles if you don't want installs showing as people with
   traits: **Settings → Data management → People settings → Enable person
   profiles → off**. Events still arrive; you just lose the person page. For a
   single-binary app this is usually what you want.

4. Add the Stripe payment link as a **goal** (`Settings → Goals`), pasting
   `https://buy.stripe.com/7sY3cuekN6z66L1c0cbEA01`. PostHog matches it against
   `$current_url` — only relevant if you ever load that page in an in-app
   webview again.

## Dashboard 1 — "Vibresia — usage"

### Row 1 — the headline numbers

| Insight | Type | Query |
|---|---|---|
| Launches | Trends | `count()` where event = `app_launched`, interval = day |
| Unique installs | Trends | `uniques(distinct_id)` where event = `app_launched` |
| New installs | Trends | `count()` where event = `app_launched` and `fresh_install = true` |
| Support clicks | Trends | `count()` where event = `checkout_started` |

### Row 2 — what people actually use

| Insight | Type | Query |
|---|---|---|
| Mode switch-overs | Bar chart | `count()` where event = `mode_changed`, breakdown by `properties.mode` |
| Audio source mix | Bar chart | `count()` where event = `source_changed`, breakdown by `properties.source` — and by `properties.via` for how people switch (the header pill was added late; `intro` is falling share) |
| Mode reached via | Bar chart | `count()` where event = `mode_changed`, breakdown by `properties.via` |
| Palette mix | Pie | `count()` where event = `palette_changed`, breakdown by `properties.palette` |
| Genre the detector picks | Bar chart | `count()` where event = `genre_detected`, breakdown by `properties.genre` |

### Row 3 — funnel and health

| Insight | Type | Query |
|---|---|---|
| Support funnel | Funnel | `app_launched` → `support_view` → `checkout_started` |
| Embed fallback rate | Trends | `count()` where event = `stripe_embed_failed` — should be **zero**; anything else means the browser/network path changed |
| Session length | Trends | `avg(properties.session_seconds / 60.0)` where event = `session_summary` |
| Per-mode dwell (histogram) | Bar chart | `properties.session_seconds` on `session_summary`, breakdown by `properties.mode` |

## Dashboard 2 — "Vibresia — support & revenue"

Small and Stripe-backed, so keep it separate:

| Insight | Type | Query |
|---|---|---|
| Coffee clicks | Trends | `count()` where event = `checkout_started`, breakdown by `properties.source` |
| Popover opens | Trends | `count()` where event = `support_view` |
| Share sheet opened | Trends | `count()` where event = `share_opened` — the ceiling on word of mouth |
| Conversion | Funnel | `support_view` → `checkout_started` |
| Paying users | Trends | `count(distinct_id)` where event = `checkout_started` |

Pair the last one against Stripe's own dashboard. If clicks are healthy but
Stripe revenue is flat, the button's fine and the *offer* isn't — that's the
comparison worth making before you touch the code again.

## HoogQL for custom insights

PostHog's insight builder covers most of the above. When you want something it
can't express, these work in the custom-HoogQL box:

```sql
-- Modes ranked by how many installs touched them at all
-- (not by switch-overs, which over-counts enthusiasts)
SELECT properties.mode AS mode, uniq(distinct_id) AS installs
FROM events
WHERE event = 'mode_changed'
GROUP BY mode
ORDER BY installs DESC

-- Palette switches per session, to spot a palette people fiddle with vs. set once
SELECT
  properties.palette AS palette,
  countIf(event = 'palette_changed') / uniq(distinct_id) AS switches_per_install
FROM events
WHERE event IN ('palette_changed', 'app_launched')
GROUP BY palette
ORDER BY switches_per_install DESC

-- Stickiness: share of installs that come back within 7 days
SELECT
  toDate(first_seen) AS cohort_day,
  uniqIf(distinct_id, day_2) / uniq(distinct_id) AS d1,
  uniqIf(distinct_id, day_7) / uniq(distinct_id) AS d7
FROM (
  SELECT
    distinct_id,
    min(timestamp) AS first_seen,
    max(toDate(timestamp)) >= min(toDate(timestamp)) + INTERVAL 1 DAY AS day_2,
    max(toDate(timestamp)) >= min(toDate(timestamp)) + INTERVAL 7 DAY AS day_7
  FROM events
  WHERE event = 'app_launched'
  GROUP BY distinct_id
)
GROUP BY cohort_day
ORDER BY cohort_day

-- Genre accuracy: how often the detector changes its mind mid-session
SELECT
  properties.genre AS genre,
  countIf(properties.confidence < 0.5) / count() AS low_confidence_share
FROM events
WHERE event = 'genre_detected'
GROUP BY genre
ORDER BY low_confidence_share DESC
```

## What the events look like

Captured live against a local sink during development:

```
app_launched    {mode: tunnel, palette: NEON, autoscan: false,
                 is_release: true, fresh_install: true,
                 surface: mac_app, app_version, build, arch, os_version,
                 locale, session_seconds}
mode_changed    {mode: llama, from_mode: tunnel, via: system}
source_changed  {source: system | microphone | demo, via: pill | intro | menu}
palette_changed {palette: TOXIC, from_palette: NEON}
genre_detected  {genre: Jazz, genre_id: 5, confidence: 0, auto: true}
genre_locked    {genre: Rock, genre_id: 2, confidence: 0.8, auto: false}
support_view    {}
share_opened    {source: shareware_link}   — the share sheet opened, not that a share happened
checkout_started{source: native_button | fallback_link | stripe_embed}
app_crashed     {reason, kind, mode, drawing, genre, source, band_on_stage,
                 frames (top 12, oldest last), breadcrumbs (last 12)}
session_summary {mode, mode_switches, palette_switches, session_seconds, …}
```

`via` on `mode_changed` is the useful one — `picker` means a deliberate click,
`auto_scan` means the cycling did it, `system` means a launch flag or restore.
Without it, auto-scan makes every mode look equally popular.

## One project, two surfaces

The landing page (`site/analytics.js`) reports here too, so installs and page
views land in the same place and can be compared. **`surface` separates them**:
`mac_app` for the app, `web` for the page. Any insight that mixes the two
without filtering on `surface` is meaningless — a `count()` of "people" would
double-count anyone who read the page and then installed.

Note also that `distinct_id` means different things on each side: a UUID in
`UserDefaults` for an install, a UUID in `localStorage` for a browser. They will
never match, and that is deliberate — there is no join key between a visitor
and an install, and adding one would mean putting an identifier in a download
link.

## Dashboard 3 — "Vibresia — landing page"

| Insight | Type | Query |
|---|---|---|
| Visits | Trends | `count()` where event = `$pageview` and `surface` = `web`, interval = day |
| Unique visitors | Trends | `uniques(distinct_id)` where event = `$pageview` |
| Downloads | Trends | `count()` where event = `download_clicked` |
| Page → download | Funnel | `$pageview` → `download_clicked` |
| Install command copied | Bar chart | `count()` where event = `install_command_copied`, breakdown by `properties.command` |
| Coffee clicks (web) | Trends | `count()` where event = `coffee_clicked`, breakdown by `properties.placement` |
| Modes people scroll to | Bar chart | `count()` where event = `mode_card_viewed`, breakdown by `properties.target` |
| Demo autoplay | Trends | `count()` where event = `demo_played` — a floor on engagement |

Two things worth watching together: if `mode_card_viewed` is concentrated on one
card but downloads aren't, the cards aren't selling what the page is; and if
`$pageview` climbs while `download_clicked` flattens, the CTA or the install
instructions are where the drop is.

## Dashboard 4 — "Vibresia — crashes"

| Insight | Type | Query |
|---|---|---|
| Crashes per day | Trends | `count()` where event = `app_crashed`, interval = day |
| Crashed installs | Trends | `uniques(distinct_id)` where event = `app_crashed` |
| Crash rate | Trends | `count()` where event = `app_crashed` ÷ `uniques(distinct_id)` where event = `app_launched` |
| Where it breaks | Bar chart | `count()` where event = `app_crashed`, breakdown by `properties.mode` |
| Which genre | Bar chart | `count()` where event = `app_crashed`, breakdown by `properties.genre` |
| Signatures | Table | `properties.frames`, grouped, to spot the same crash from different installs |

`mode` and `genre` are the reason this dashboard exists: a crash that only
happens in band mode, or only in one genre, is a much shorter conversation than
"it crashed sometimes". Group the `frames` property to find identical stacks
across installs.

Crashes only upload when the user has anonymous usage switched on in the app —
a crash report is usage data by another name, and the switch is theirs. Reports
stay on disk either way, and the app's **Vibresia → Report a Problem…** menu
item emails one to us directly.
