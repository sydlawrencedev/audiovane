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

# The /api/notify token counts as well: it is the thing standing between a
# stranger and our Discord channel now that the app reports to us. So does
# the share token, which is what stops the site's share endpoint being used
# as free storage by anyone who finds it.
matches=$(git grep -InE 'NOTIFY_TOKEN\s*=\s*["'\'']?[A-Za-z0-9_-]{16,}' -- . 2>/dev/null || true)
matches=$(git grep -InE 'SHARE_TOKEN\s*=\s*["'\'']?[A-Za-z0-9_-]{16,}' -- . 2>/dev/null || true)

# Include .env / .dev.vars in the sweep even though they're ignored: the point
# is to catch the moment one of them gets force-added.
matches=$(git grep -InE 'discord(app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_.-]{20,}' -- . 2>/dev/null || true)
for f in .env .dev.vars; do
  [ -f "$f" ] || continue
  if grep -qE 'discord(app)?\.com/api/webhooks/' "$f"; then
    matches+="${f}: contains a Discord webhook URL (ignored file — do not commit it)"
  fi
  if grep -qE '^\s*NOTIFY_TOKEN\s*=\s*\S{16,}' "$f"; then
    matches+="${f}: contains the /api/notify token (ignored file — do not commit it)"
  fi
  if grep -qE '^\s*SHARE_TOKEN\s*=\s*\S{16,}' "$f"; then
    matches+="${f}: contains the share token (ignored file — do not commit it)"
  fi
done

if [ -n "$matches" ]; then
  echo "A secret that shouldn't be in git found in the working tree:" >&2
  echo "$matches" >&2
  echo "" >&2
  echo "Treat it as leaked: rotate the webhook in Discord (npx wrangler secret put" >&2
echo "DISCORD_WEBHOOK_URL), the notify token (NOTIFY_TOKEN) and the share token" >&2
echo "(SHARE_TOKEN), then rebuild." >&2
  exit 1
fi
echo "no webhook URLs, notify tokens or share tokens in tracked files"
