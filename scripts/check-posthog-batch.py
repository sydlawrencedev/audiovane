#!/usr/bin/env python3
"""Check both surfaces send a JSON array of events to PostHog's /batch/.

A matching project key isn't enough. Both surfaces used to post

    {"api_key": "...", "batch": [ {...}, {...} ]}

to /batch/. PostHog parses that, replies 200 with {"status":"Ok"}, and records
nothing — the object it inspects has no `event` field, so there is no event to
record. Every status code looks like success, which is exactly why an empty
project is hard to diagnose from the code.

/batch/ takes a JSON array, one event per element. So:

  * the body must be the array itself, not a wrapper holding it;
  * the web client must say application/json, because text/plain can't carry an
    array (and PostHog rejects multi-line ndjson with a 400).

Split out of check-posthog.sh so both checks can be run on their own.
"""
import os
import re
import sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))

js_path = os.path.join(root, "site/analytics.js")
swift_path = os.path.join(root, "VisualiserMac/Sources/VisualiserMac/Analytics/Analytics.swift")

problems = []

for path in (js_path, swift_path):
    if not os.path.exists(path):
        print(f"missing {path}")
        sys.exit(1)

def without_comments(text):
    """Drops line comments so a comment explaining the fix doesn't trip the check.

    Without this, the comment that documents why the wrapper was wrong matches
    the very pattern being looked for, and the check fails on correct code.
    """
    out = []
    for line in text.splitlines():
        # Good enough for both languages here: neither file has a string
        # literal containing "//" that this would mangle.
        out.append(line.split("//", 1)[0])
    return "\n".join(out)


js = without_comments(open(js_path).read())
swift = without_comments(open(swift_path).read())

# The wrapper, in either surface. Keys are optional-quoted because the two
# languages differ: the JS writes {api_key: KEY, batch: batch} and Swift writes
# ["api_key": key, "batch": batch]. Matching only the quoted form lets the JS
# through, which is the half nobody would think to check.
WRAPPER = re.compile(r'\{\s*"?api_key"?\s*:\s*[A-Za-z_"]+\s*,\s*"?batch"?\s*:')
for name, body in (("site/analytics.js", js), ("Analytics.swift", swift)):
    if WRAPPER.search(body):
        problems.append(f"{name} wraps the batch as {{api_key, batch}}")

# The web client has to send the array as JSON.
if "text/plain" in js:
    problems.append("site/analytics.js still posts text/plain; /batch/ cannot read an array from it")
if "application/json" not in js:
    problems.append("site/analytics.js doesn't send application/json to /batch/")

# The app must hit /batch/ and serialise the array itself.
if 'appendingPathComponent("batch")' not in swift:
    problems.append("Analytics.swift no longer posts to /batch/")
if "withJSONObject: batch)" not in swift:
    problems.append("Analytics.swift doesn't serialise the batch array directly")

if problems:
    print("PostHog batch shape is wrong:")
    for problem in problems:
        print(f"  x {problem}")
    print("  /batch/ takes a JSON array of events. A wrapper object returns 200 and records nothing.")
    sys.exit(1)

print("both surfaces send a JSON array of events to /batch/")
