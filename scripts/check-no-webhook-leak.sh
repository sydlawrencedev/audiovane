#!/bin/bash
# Fails if a Discord webhook URL is anywhere in the tracked tree.
#
# Delphina learned this the expensive way: one webhook URL got committed and
# then baked into dozens of release tags, where it stayed long after it was
# supposed to be rotated. The URL is a credential — anyone holding it can post
# to the channel, and it can't be revoked without recreating it in Discord.
#
# The real value lives in a Worker secret (`wrangler secret put
# DISCORD_WEBHOOK_URL`); `.dev.vars` holds the local copy. Neither is tracked.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Include .env / .dev.vars in the sweep even though they're ignored: the point
# is to catch the moment one of them gets force-added.
matches=$(git grep -InE 'discord(app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_.-]{20,}' -- . 2>/dev/null || true)
for f in .env .dev.vars; do
  [ -f "$f" ] || continue
  if grep -qE 'discord(app)?\.com/api/webhooks/' "$f"; then
    matches+="${f}: contains a Discord webhook URL (ignored file — do not commit it)"
  fi
done

if [ -n "$matches" ]; then
  echo "Discord webhook URL found in the working tree:" >&2
  echo "$matches" >&2
  echo "" >&2
  echo "Treat it as leaked: recreate the webhook in Discord, then npx wrangler secret put DISCORD_WEBHOOK_URL" >&2
  exit 1
fi
echo "no Discord webhook URLs in tracked files"
