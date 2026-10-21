#!/usr/bin/env python3
"""Check the PostHog project key actually records, by reading an event back.

The other two checks here are static. One compares the key between the site and
the app; the other checks the shape of the batch. Neither can tell a live
project token from a dead one — a dead token matches itself just fine, and a
correctly shaped POST to a dead token is still a correct shape.

That gap is not theoretical. PostHog's /batch/ endpoint answers

    HTTP 200 {"status":"Ok"}

for *any* syntactically valid phc_ key, including one belonging to a deleted or
rotated project. It only 401s when the payload has no api_key at all. So both
surfaces, and every status code they are able to see, report success while every
event is dropped. That is the "empty project, no error anywhere" state, and it
is how several releases shipped unnoticed.

Telling recording apart from accepting means reading an event back, which needs
a personal API key (phx_...). It is read-only and never ships: it lives in
VisualiserMac/.env alongside the project key, and that file is gitignored.

Skipped, loudly, when no personal API key is configured. Add one to make this
enforced:

    # PostHog -> Settings -> Personal API keys -> Create.
    # Needs read scope only. Copy to VisualiserMac/.env.
    POSTHOG_PERSONAL_API_KEY=phx_xxxxxxxxxxxxxxxxxxxx
    POSTHOG_PROJECT_ID=123456

The canary event it posts is named posthog_canary and carries no real data —
delete it from PostHog afterwards if it bothers you.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

EVENT = "posthog_canary"
DISTINCT_ID = "posthog-canary-check"
# Ingestion to queryable is usually seconds, but PostHog's API can lag well past
# that under load. Failing early would produce flaky releases, which trains
# people to re-run a check that was telling the truth.
WAIT_SECONDS = 300
POLL_SECONDS = 5
# The events endpoint has been measured answering in 40-47s on a cold query,
# well past urllib's usual patience. A read that gives up at 20s looks exactly
# like a dead project, which is the one conclusion this script must never get
# wrong. It has to outlast the slowest response we have actually seen.
READ_TIMEOUT = 90


def load_env(path):
    """Reads KEY=VALUE lines out of .env. Ignores comments and export."""
    values = {}
    if not os.path.exists(path):
        return values
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r'(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"?([^"#]*)"?\s*$', line)
        if m:
            values.setdefault(m.group(1), m.group(2).strip())
    return values


def get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=READ_TIMEOUT) as response:
        return json.loads(response.read().decode())


def post(url, body, headers):
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=READ_TIMEOUT) as response:
        return response.status, response.read().decode()


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))
    env = load_env(os.path.join(root, "VisualiserMac/.env"))
    for name, value in ((k, v) for k, v in os.environ.items()
                        if k.startswith("POSTHOG_")):
        env[name] = value  # real environment wins over the file

    project_key = env.get("POSTHOG_KEY", "")
    host = env.get("POSTHOG_HOST", "https://us.i.posthog.com").rstrip("/")
    personal = env.get("POSTHOG_PERSONAL_API_KEY", "")
    project_id = env.get("POSTHOG_PROJECT_ID", "")

    if not personal or not project_id:
        print("SKIPPED: no PostHog personal API key, so nothing can confirm events land.")
        print(f"  {EVENT} was not posted. To enable this check, add to VisualiserMac/.env:")
        print("    POSTHOG_PERSONAL_API_KEY=phx_...")
        print("    POSTHOG_PROJECT_ID=<numeric id from PostHog project settings>")
        print("  Until then a rotated or deleted project key will pass every other check here.")
        return 0

    if not project_key.startswith("phc_"):
        print(f"No usable project key in VisualiserMac/.env (got {project_key[:8]!r}).")
        return 1

    event = {
        "api_key": project_key,
        "event": EVENT,
        "distinct_id": DISTINCT_ID,
        "properties": {"source": "check-posthog-live.py"},
        "$lib": "posthog-canary",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
    }
    try:
        status, body = post(host + "/batch/",
                            json.dumps([event]).encode(),
                            {"Content-Type": "application/json"})
    except urllib.error.HTTPError as e:
        print(f"PostHog rejected the canary outright: HTTP {e.code} {e.reason}")
        return 1

    # A 200 here proves nothing at all — see the module docstring. Say so, so
    # nobody reads this line as confirmation on its own.
    print(f"Posted the canary ({status} {body.strip()}) — not evidence of anything on its own.")

    query = (f"{host}/api/projects/{project_id}/events/"
             f"?event={EVENT}&limit=5")
    headers = {"Authorization": f"Bearer {personal}"}
    deadline = time.time() + WAIT_SECONDS
    last_error = None
    while time.time() < deadline:
        try:
            found = get(query, headers).get("results", [])
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                print(f"Could not read events back: HTTP {e.code} {e.reason}")
                print("  The personal API key is wrong, lacks read scope, or is scoped to a")
                print("  different project than POSTHOG_PROJECT_ID.")
                return 1
            if e.code == 404:
                print(f"Could not read events back: HTTP 404. POSTHOG_PROJECT_ID={project_id}")
                print("  is not a project in this account — check Project settings.")
                return 1
            # 429 and 5xx are PostHog having a bad minute, not a wrong answer.
            # us.i.posthog.com returns 503 under load and then recovers inside
            # seconds. Failing on one would mean this script cries wolf about a
            # working project, which is the exact failure mode it was written to
            # remove. Keep polling and let the deadline decide.
            last_error = f"HTTP {e.code} {e.reason}"
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last_error = e
        else:
            if found:
                print(f"OK: {EVENT} came back from project {project_id}. Ingestion works.")
                return 0
        time.sleep(POLL_SECONDS)

    print(f"FAIL: posted {EVENT}, but it never came back after {WAIT_SECONDS}s.")
    if last_error:
        print(f"  Last read error: {last_error}")
        if isinstance(last_error, (TimeoutError, urllib.error.URLError)):
            print("  That is a timeout, not a rejected read — the request never got an")
            print("  answer. PostHog's events API has been measured answering in ~45s on a")
            print("  cold query, so this says nothing either way about the project key.")
            print("  Re-run before reading anything into it.")
    print("  If the reads are answering and the canary still isn't there, check in order:")
    print(f"    1. Project {project_id}'s API key still matches phc_... in VisualiserMac/.env")
    print("    2. The key belongs to the project you are actually looking at")
    print("    3. The project has not hit its event quota (PostHog drops silently)")
    print("    4. Data management -> filtering is not discarding these events")
    return 1


if __name__ == "__main__":
    sys.exit(main())