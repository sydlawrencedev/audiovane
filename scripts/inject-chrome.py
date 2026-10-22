#!/usr/bin/env python3
"""Put the shared navbar and footer into every page, from one source of truth.

There is no templating on the way to Cloudflare Workers Static Assets — the
HTML that ships is the HTML in the repo. So "every page has the same navbar" is
either true because one file owns it, or it is true until someone edits one page
and forgets the other twenty.

Each page keeps a marked region:

    <!-- chrome:nav -->
    ...generated...
    <!-- /chrome:nav -->

Running this rewrites the inside of those regions from site/_partials/. Running
it with --check only reports, which is what release.sh does: three definitions
of `.brand` is not a problem on its own, three definitions that quietly drift
apart is.

    ./scripts/inject-chrome.py            rewrite every page
    ./scripts/inject-chrome.py --check    fail if any page is out of date
"""
import os
import re
import sys

REGIONS = {"nav": "nav.html", "footer": "footer.html"}

# The share pages are generated, so they are not in the repo as a thing you
# edit — but they are in the repo as files that ship, so they are checked like
# anything else. generate-share-pages.py calls this at the end for that reason.
PAGES = ["site/index.html", "site/agents.html", "site/vibescapes.html", "site/vibe.html",
         "site/admin.html"]


def pages(root):
    found = list(PAGES)
    share = os.path.join(root, "site", "share")
    if os.path.isdir(share):
        for name in sorted(os.listdir(share)):
            if name.endswith(".html"):
                found.append(f"site/share/{name}")
    return [p for p in found if os.path.exists(os.path.join(root, p))]


def block(region, partial):
    """The marked region, with the partial's lines re-indented to match."""
    body = open(partial).read().strip("\n")
    return f"<!-- chrome:{region} -->\n{body}\n<!-- /chrome:{region} -->"


def inject(text, region, partial):
    pattern = re.compile(
        r"^(?P<indent>[ \t]*)<!-- chrome:" + region + r" -->.*?"
        r"^[ \t]*<!-- /chrome:" + region + r" -->",
        re.S | re.M,
    )
    match = pattern.search(text)
    if not match:
        return None

    indent = match.group("indent")
    body = open(partial).read().strip("\n")
    # Match the indentation the page already uses, so an injected navbar lines
    # up with the markup around it instead of jumping to column zero.
    body = "\n".join(indent + line if line.strip() else line for line in body.split("\n"))
    return pattern.sub(lambda m: f"{indent}<!-- chrome:{region} -->\n{body}\n"
                                  f"{indent}<!-- /chrome:{region} -->", text, count=1)


def main():
    # The root is whatever positional argument is left after the flags, not
    # argv[1] — release.sh passes `--check` first, and treating that as the
    # root makes every path resolve to nonsense and every page look unbuildable.
    check = "--check" in sys.argv
    positional = [a for a in sys.argv[1:] if not a.startswith("-")]
    root = positional[0] if positional else os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))

    partials = {r: os.path.join(root, "site", "_partials", f)
                for r, f in REGIONS.items()}
    for region, path in partials.items():
        if not os.path.exists(path):
            print(f"missing site/_partials/{REGIONS[region]} — nothing to inject.")
            return 1

    changed, missing, drift = [], [], []
    for page in pages(root):
        full = os.path.join(root, page)
        original = open(full).read()
        text = original
        for region, partial in partials.items():
            result = inject(text, region, partial)
            if result is None:
                missing.append(f"{page} (no chrome:{region} region)")
                text = None
                break
            text = result
        if text is None:
            continue
        if text == original:
            continue
        if check:
            drift.append(page)
        else:
            open(full, "w").write(text)
            changed.append(page)

    for page in missing:
        print(f"  x {page}")

    if check:
        if drift:
            print("Shared navbar/footer is out of date on:")
            for page in drift:
                print(f"  x {page}")
            print("  Fix with ./scripts/inject-chrome.py")
            return 1
        if missing:
            print("Pages are missing a shared navbar/footer region.")
            return 1
        print(f"every page's navbar and footer matches site/_partials ({len(pages(root))} pages)")
        return 0

    if missing:
        print("Pages are missing a shared navbar/footer region:")
        for page in missing:
            print(f"  x {page}")
        return 1
    if changed:
        for page in changed:
            print(f"  updated {page}")
        print(f"navbar and footer injected into {len(changed)} page(s)")
    else:
        print("every page already matched site/_partials")
    return 0


if __name__ == "__main__":
    sys.exit(main())