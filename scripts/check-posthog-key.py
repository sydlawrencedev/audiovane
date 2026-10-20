#!/usr/bin/env python3
"""Check the landing page and the app report into the same PostHog project.

Split out of check-posthog.sh so both checks can be run on their own.
"""
import os
import re
import sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))

env = os.path.join(root, "VisualiserMac/.env")
html = open(os.path.join(root, "site/index.html")).read()


def from_env():
    if not os.path.exists(env):
        print("VisualiserMac/.env is missing — can't check the analytics key.")
        sys.exit(1)
    for line in open(env):
        m = re.match(r'\s*POSTHOG_KEY\s*=\s*"?([A-Za-z0-9_]+)"?', line)
        if m:
            return m.group(1)
    print("VisualiserMac/.env has no POSTHOG_KEY.")
    sys.exit(1)


site = re.search(r'<meta name="posthog-key" content="([^"]*)"', html)

key = from_env()
if not site or not site.group(1):
    print('site/index.html has no <meta name="posthog-key"> — the landing page won\'t report.')
    sys.exit(1)
if site.group(1) != key:
    print("PostHog key mismatch:")
    print(f"  VisualiserMac/.env : {key}")
    print(f"  site/index.html    : {site.group(1)}")
    print("Update the meta tag to match .env (the site key is public by design).")
    sys.exit(1)
print(f"site and app share PostHog project {key[:8]}...")
