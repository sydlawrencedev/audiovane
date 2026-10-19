# PostHog dashboard — AudioVane

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
   `https://buy.stripe.com/fZu14mb8B9Li9Xd5BObEA00`. PostHog matches it against
   `$current_url` — only relevant if you ever load that page in an in-app
   webview again.

## Dashboard 1 — "AudioVane — usage"

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

## Dashboard 2 — "AudioVane — support & revenue"

Small and Stripe-backed, so keep it separate:

| Insight | Type | Query |
|---|---|---|
| Coffee clicks | Trends | `count()` where event = `checkout_started`, breakdown by `properties.source` |
| Popover opens | Trends | `count()` where event = `support_view` |
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
                 app_version, build, arch, os_version, locale, session_seconds}
mode_changed    {mode: llama, from_mode: tunnel, via: system}
palette_changed {palette: TOXIC, from_palette: NEON}
genre_detected  {genre: Jazz, genre_id: 5, confidence: 0, auto: true}
genre_locked    {genre: Rock, genre_id: 2, confidence: 0.8, auto: false}
support_view    {}
checkout_started{source: native_button | fallback_link | stripe_embed}
session_summary {mode, mode_switches, palette_switches, session_seconds, …}
```

`via` on `mode_changed` is the useful one — `picker` means a deliberate click,
`auto_scan` means the cycling did it, `system` means a launch flag or restore.
Without it, auto-scan makes every mode look equally popular.
