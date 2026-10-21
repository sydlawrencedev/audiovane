#!/usr/bin/env python3
"""Check the share page's browser copy of the shaders matches the app's.

site/share/preview.js embeds a copy of the app's prelude, wrapper, vertex shader
and grade shader, because a browser has to compile them itself and there's no
way to fetch them from the app at runtime. A copy is a promise that it gets
refreshed when the original changes.

It didn't get refreshed once already: `fbm` was added to the prelude, the app
got it, and the browser's copy did not. Every shared vibescape that used noise
then failed to draw, on the live site, with nothing on the page to say why —
the picture just wasn't there. Found by rendering a shared link in a browser,
which is the only thing that would have caught it.

So this runs at release time and fails on any difference.

  python3 scripts/check-preview-glsl.py
"""
import os
import re
import sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))

fun = os.path.join(root, "VisualiserMac/Sources/VisualiserMac/Render/FunShaders.swift")
sha = os.path.join(root, "VisualiserMac/Sources/VisualiserMac/Render/Shaders.swift")
preview = os.path.join(root, "site/share/preview.js")

for path in (fun, sha, preview):
    if not os.path.exists(path):
        print(f"missing {path}")
        sys.exit(1)


def swift_block(path, name):
    src = open(path, encoding="utf-8").read()
    m = re.search(r'static let ' + name + r' = """\n(.*?)\n    """', src, re.S)
    if not m:
        print(f"{os.path.basename(path)} has no `static let {name}`")
        sys.exit(1)
    body = m.group(1)
    return "\n".join(l[4:] if l.startswith("    ") else l for l in body.split("\n"))


def unescape(text):
    """Undo what the escaping in preview.js did, so the two can be compared."""
    return text.replace("\\${", "${").replace("\\`", "`").replace("\\\\", "\\")


def embedded(name):
    js = open(preview, encoding="utf-8").read()
    m = re.search(r'var ' + name + r' = `(.*?)`;', js, re.S)
    if not m:
        print(f"preview.js has no `var {name}`")
        sys.exit(1)
    return unescape(m.group(1))


PAIRS = [
    ("PRELUDE", swift_block(fun, "prelude")),
    ("WRAPPER", swift_block(fun, "customWrapper")),
    ("LIQUID_VS", swift_block(sha, "liquidVS")),
    ("GRADE_FS", swift_block(sha, "gradeFS")),
]

bad = []
for name, expected in PAIRS:
    got = embedded(name)
    if got != expected:
        # Say which helper is missing or extra, because "the files differ" is
        # not something you can act on.
        want = set(re.findall(r'\b(?:float|vec[234]|mat[234])\s+(\w+)\s*\(', expected))
        have = set(re.findall(r'\b(?:float|vec[234]|mat[234])\s+(\w+)\s*\(', got))
        missing = sorted(want - have)
        extra = sorted(have - want)
        detail = []
        if missing:
            detail.append("browser copy is missing " + ", ".join(missing))
        if extra:
            detail.append("browser copy has extra " + ", ".join(extra))
        if not detail:
            detail.append(f"{len(got.splitlines())} lines vs {len(expected.splitlines())}")
        bad.append(f"{name}: " + "; ".join(detail))

if bad:
    print("site/share/preview.js has drifted from the app's shaders:")
    for b in bad:
        print(f"  x {b}")
    print()
    print("  A shared vibescape won't draw in the browser if the prelude is stale.")
    print("  Regenerate the embedded shaders, or add noise helpers to the")
    print("  reference doc too if that's what changed.")
    sys.exit(1)

print(f"share page shaders match the app ({len(PAIRS)} blocks)")
