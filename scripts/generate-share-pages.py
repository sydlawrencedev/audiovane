#!/usr/bin/env python3
"""Generates the per-vibescape share HTML pages at `site/share/<slug>.html`
and the lookup table at `site/share/manifest.json`.

`site/share/index.html` — the page custom vibscape shares land on — is
hand-written, not generated. It lives in the `share/` directory on purpose:
Cloudflare Workers Static Assets serve a directory's index.html for both
`/share` and `/share/`, so no rewrite is needed. A rewrite in `_redirects`
was the obvious alternative and it 307s to itself forever, because a rule's
source matches on path *prefix* — `/share -> /share.html` also matches
`/share.html`, which is its own destination. See the note in
`site/_redirects`.

Each generated HTML is a static file with full `og:*` meta tags pointing at
its per-vibescape share graphic, the Open-in-Vibresia button wired to
`vibresia://open?p=<slug>`, and the same chrome as the homepage. Crawlers
(Twitter, Slack, iMessage) read the meta and produce a card with the right
title, description and image without running JavaScript.

Idempotent — re-running overwrites. Slugs, titles, descriptions and key
hints come from `site/index.html` so a name change in the homepage can't
silently drift from the share pages.

Run from the repo root:
  python3 scripts/generate-share-pages.py
"""
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INDEX_HTML = ROOT / "site" / "index.html"
OUT_DIR = ROOT / "site" / "share"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def parse_vibscape_cards() -> list[dict]:
    """Read the homepage and pull (slug, title, description) from each vibscape card."""
    html = INDEX_HTML.read_text(encoding="utf-8")

    # Split on the card opener, then parse each card on its own. This used to be
    # one regex across the whole page, anchored on the "01 · KEY 1" label that
    # used to sit above every title — the label that has since been removed from
    # the cards. Anchoring on the opener instead means each card can only ever
    # match itself, so a card that drifts takes out one card rather than
    # silently pairing one card's title with another's description.
    #
    # Only the shipped vibscapes carry data-vibscape; the Auto Scan card
    # doesn't, because it isn't shareable.
    cards = []
    for chunk in html.split('<article class="vibscape" data-vibscape="')[1:]:
        slug = chunk[:chunk.index('"')].strip()
        head = re.search(
            r'<h3>(?P<title>[^<]+)</h3>(?:\s*<p>(?P<desc>.*?)</p>)?',
            chunk, re.DOTALL)
        if not head:
            sys.exit(f'vibscape card "{slug}" has no <h3> — homepage template drifted')
        cards.append({
            "slug": slug,
            "title": head["title"].strip(),
            "desc": (head["desc"] or "").strip(),
        })
    if not cards:
        sys.exit("no vibscape cards parsed from site/index.html — template likely drifted")
    return cards


def render(slug: str, title: str, desc: str) -> str:
    # Hand-stamped canonical URL and og:image so the static file is correct
    # the moment it lands, without any client-side rewrite. Width/height
    # mirror the existing share image and what Twitter / Slack / iMessage
    # accept for preview cards.
    safe_title = title.replace("&", "&amp;").replace("'", "&#39;")
    safe_desc = desc.replace("&", "&amp;").replace("'", "&#39;")
    og_image = f"https://vibresia.com/share/{slug}.jpg"
    canonical = f"https://vibresia.com/share/{slug}"

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{safe_title} — Vibresia</title>
<meta name="description" content="{safe_desc}">
<link rel="canonical" href="{canonical}">
<meta name="robots" content="index, follow, max-image-preview:large">
<meta name="theme-color" content="#06010d">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Vibresia">
<meta property="og:url" content="{canonical}">
<meta property="og:title" content="{safe_title} — a Vibresia vibescape">
<meta property="og:description" content="{safe_desc}">
<meta property="og:image" content="{og_image}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="{safe_title}, a Vibresia vibescape by Minith Labs">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{safe_title} — a Vibresia vibescape">
<meta name="twitter:description" content="{safe_desc}">
<meta name="twitter:image" content="{og_image}">
<meta name="posthog-key" content="phc_pzYyxiM6u2pYa6FbCkRY8HPudHDopu5LrTwnoamHaeg2">
<meta name="posthog-host" content="https://us.i.posthog.com">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="{og_image}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Space+Grotesk:wght@400;500;700&display=swap" media="print" onload="this.media='all'">
<noscript><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Space+Grotesk:wght@400;500;700&display=swap"></noscript>
<link rel="stylesheet" href="/share/share-page.css">
</head>
<body>
<div class="wrap">
  <a class="brand" href="/">
    <svg viewBox="0 0 32 32" aria-hidden="true"><path d="M3 16 L7 16 L9 8 L13 24 L17 12 L21 20 L25 16 L29 16" stroke="#ff2bd6" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>
    VIBRESIA
  </a>

  <section class="hero">
    <h1>{safe_title}.</h1>
    <p class="lede">{safe_desc}</p>
  </section>

  <div class="shot">
    <!-- Moving rather than still: the app renders these, so the clip is the
         vibscape rather than a picture of it. The poster is the same render as
         a JPEG, so there is a frame there from the first paint and for anyone
         whose browser won't play it — and it stays the og:image, because a
         crawler that fetches a link has no video and no JavaScript. -->
    <video autoplay muted loop playsinline preload="metadata"
           poster="/share/{slug}.jpg"
           width="1200" height="630"
           aria-label="{safe_title}, a Vibresia vibescape by Minith Labs">
      <source src="/share/{slug}.mp4" type="video/mp4">
    </video>
  </div>

  <div class="cta-row">
    <a class="btn primary" href="#" data-share-open data-share-slug="{slug}">Open in Vibresia</a>
    <a class="btn coffee" href="/download?src=share_{slug}" data-share-download hidden>Download for Mac</a>
  </div>

  <p class="share-cta"><small>Press <strong>Open in Vibresia</strong> and the app will switch to {safe_title}. You’ll need Vibresia on your Mac — free, no account.</small></p>

  <p class="credit">Made with ❤ by Minith Labs</p>
</div>

<script src="/analytics.js" defer></script>
<script src="/share/share-page.js"></script>
</body>
</html>
"""


def main() -> int:
    cards = parse_vibscape_cards()
    for card in cards:
        out = OUT_DIR / f"{card['slug']}.html"
        out.write_text(render(**card), encoding="utf-8")
        print(f"[share-pages] wrote {out.relative_to(ROOT)}")

    # site/share/index.html is hand-written and is what /share serves, so it is
    # checked rather than generated — if it goes missing, every custom-vibscape
    # share link 404s, and that should be a loud failure here.
    if not (OUT_DIR / "index.html").exists():
        print("[share-pages] site/share/index.html is missing — custom vibscape "
              "shares would 404. Restore it before deploying.", file=sys.stderr)
        return 1

    # Lookup table so the JS in /share can suggest other built-ins
    # and validate slugs without having to redeploy.
    manifest = {
        "generated": "regenerate with scripts/generate-share-pages.py",
        "base": "https://vibresia.com",
        "built_ins": [
            {"slug": c["slug"], "title": c["title"]}
            for c in cards
        ],
    }
    manifest_path = OUT_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[share-pages] wrote {manifest_path.relative_to(ROOT)}")

    print(f"[share-pages] {len(cards)} vibscapes generated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
