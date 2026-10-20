// Vibresia's landing-page Worker.
//
// The site is static, but downloads need a server: that's where we can say
// *someone* downloaded, not just *someone clicked*, and it's where the Discord
// webhook can live without ever touching the browser.
//
// Everything not listed here falls through to the static assets in ./site,
// which still get their `_headers` and `_redirects` treatment on the way out.
//
// The Discord side follows delphina's pattern (plain webhook, embed with a
// colour per priority, never let a notification failure break the user's
// path) and adds the three things delphina's own notifications are missing
// because they run inline in a request: a timeout, one retry, and
// `ctx.waitUntil` so Discord can never delay a download.

const CANONICAL_HOST = "vibresia.com";
const CANONICAL_SITE = `https://${CANONICAL_HOST}/`;

// The host the app used to live on. It's still attached to this Worker, so
// requests to it are answered — with a permanent redirect to the new name,
// keeping the path and the query string. That's what makes the old install
// command, the old links in other people's posts and the old bookmark keep
// working: `curl -fsSL https://audiovane.minithlabs.com/install.sh | bash`
// still finds the installer, now at the new address.
const LEGACY_HOSTS = ["audiovane.minithlabs.com"];

const RELEASE_ZIP =
  "https://github.com/sydlawrencedev/vibresia/releases/latest/download/Vibresia.zip";

// Same table as delphina's PRIORITY_STYLE, so a download and a signup look
// like the same family of message.
const STYLES = {
  urgent: { color: 0xe74c3c, emoji: "🚨" },
  high: { color: 0xe67e22, emoji: "⚠️" },
  default: { color: 0x3498db, emoji: "🔔" },
  good: { color: 0x2ecc71, emoji: "🎉" },
};

// Anyone who isn't a person clicking a button: link checkers, uptime probes,
// the preview bot that opens every link in a PR. A download is worth telling
// us about; a crawler following a link is not.
const AUTOMATION = /bot|crawler|spider|slurp|curl|wget|python|headless|preview|lighthouse|monitoring|uptime|facebookexternalhit|discordbot|slackbot|whatsapp|telegrambot|linkedinbot|facebookbot|twitterbot|embedly|quora link preview|showyoubot|outbrain|vkshare|w3c_validator|whatsapp/i;

const DISCORD_TITLE_LIMIT = 256;
const DISCORD_FIELD_LIMIT = 1024;
const DISCORD_DESC_LIMIT = 4096;

// Per-isolate, so it is a nudge rather than a guarantee: it exists to stop a
// double-clicked button posting twice, not to defend the webhook. Rate limits
// at Discord and rotating the secret do that job.
const MIN_SECONDS_BETWEEN = 5;
const MAX_PER_HOUR = 30;
// Errors are rarer but more valuable, and they arrive from installs rather
// than from the site, so they get their own budget — including their own
// cooldown, because one broken install can fail every second while the user
// fights with a permission dialog.
const ERROR_MIN_SECONDS_BETWEEN = 60;
const ERROR_MAX_PER_HOUR = 60;
let lastSentAt = 0;
let sentThisHour = 0;
let hourStartedAt = 0;
let lastErrorAt = 0;
let errorsThisHour = 0;
let errorHourStartedAt = 0;

function truncate(value, limit) {
  const text = String(value ?? "");
  return text.length > limit ? text.slice(0, limit - 3) + "..." : text;
}

export function isDiscordEnabled(env) {
  return env.DISCORD_NOTIFICATIONS_ENABLED === "true" && !!env.DISCORD_WEBHOOK_URL;
}

function looksAutomated(request) {
  const agent = request.headers.get("user-agent") || "";
  return !agent || AUTOMATION.test(agent);
}

function rateLimited() {
  const now = Date.now();
  if (now - hourStartedAt > 3_600_000) {
    hourStartedAt = now;
    sentThisHour = 0;
  }
  if (now - lastSentAt < MIN_SECONDS_BETWEEN * 1000) return true;
  if (sentThisHour >= MAX_PER_HOUR) return true;
  lastSentAt = now;
  sentThisHour += 1;
  return false;
}

// The debounce lives in module scope because that is where per-isolate state
// lives. Exported so the tests can clear it between cases.
export function resetRateLimiter() {
  lastSentAt = 0;
  sentThisHour = 0;
  hourStartedAt = 0;
  lastErrorAt = 0;
  errorsThisHour = 0;
  errorHourStartedAt = 0;
}

// Same idea, separate budget: a download in a loop shouldn't silence the one
// crash report that matters.
function errorRateLimited() {
  const now = Date.now();
  if (now - errorHourStartedAt > 3_600_000) {
    errorHourStartedAt = now;
    errorsThisHour = 0;
  }
  if (now - lastErrorAt < ERROR_MIN_SECONDS_BETWEEN * 1000) return true;
  if (errorsThisHour >= ERROR_MAX_PER_HOUR) return true;
  lastErrorAt = now;
  errorsThisHour += 1;
  return false;
}

// Kept pure and exported so the payload can be asserted on without a network.
// `firstSeen` means "this browser has downloaded before" — the page puts it in
// the link's query string, since a plain link click can't carry a header.
export function buildDownloadEmbed({ source, referer, country, city, agent, firstSeen }) {
  const style = STYLES.good;
  const fields = [];

  if (source) fields.push({ name: "Source", value: truncate(source, DISCORD_FIELD_LIMIT), inline: true });
  if (country) {
    const where = city ? `${city}, ${country}` : country;
    fields.push({ name: "Where", value: truncate(where, DISCORD_FIELD_LIMIT), inline: true });
  }
  fields.push({
    name: "Referrer",
    value: truncate(referer || "typed or followed directly", DISCORD_FIELD_LIMIT),
    inline: false,
  });
  fields.push({
    name: "Browser",
    value: truncate(agent || "unknown", DISCORD_FIELD_LIMIT),
    inline: false,
  });
  fields.push({
    name: "Seen before",
    value: firstSeen
      ? "yes — this browser has downloaded before"
      : "no — first download from this browser",
    inline: true,
  });

  return {
    username: undefined, // filled in from env at send time
    embeds: [
      {
        author: { name: "Vibresia" },
        title: `${style.emoji} Somebody downloaded Vibresia`,
        description: "The 302 is about to hand them the latest release.",
        url: RELEASE_ZIP,
        color: style.color,
        fields,
        footer: { text: "vibresia.com" },
        timestamp: new Date().toISOString(),
      },
    ],
  };
}

async function postDiscord(env, payload) {
  const body = JSON.stringify(payload);
  // Discord usually answers in well under a second; five is a hung connection,
  // and the caller is a download we shouldn't keep waiting on.
  const send = () =>
    fetch(env.DISCORD_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      signal: AbortSignal.timeout(5000),
    });

  let response;
  try {
    response = await send();
  } catch (error) {
    // One retry: a dropped connection is the common transient failure, and a
    // second attempt costs nothing when the first was a network blip.
    console.warn("[discord] first attempt failed, retrying:", error.message);
    try {
      response = await send();
    } catch (retryError) {
      console.error("[discord] giving up:", retryError.message);
      return { ok: false, error: retryError.message };
    }
  }

  if (response.ok) return { ok: true, status: response.status };
  // 429 and 5xx are worth one more go; 400 (a bad payload) never is.
  const retryable = response.status === 429 || response.status >= 500;
  const detail = await response.text().catch(() => "");
  console.error(`[discord] HTTP ${response.status}: ${detail.slice(0, 200)}`);
  if (!retryable) return { ok: false, status: response.status };

  try {
    const second = await send();
    if (second.ok) return { ok: true, status: second.status };
    console.error(`[discord] retry got HTTP ${second.status}`);
  } catch (error) {
    console.error("[discord] retry failed:", error.message);
  }
  return { ok: false, status: response.status };
}

function handleDownload(request, url, env, ctx) {
  const source = url.searchParams.get("src") || "";
  const referer = request.headers.get("referer") || "";
  const agent = request.headers.get("user-agent") || "";
  // The page appends this to the link itself: "0" on the first download,
  // "1" after. It means "has this browser downloaded before", and says no more
  // than that.
  const seen = url.searchParams.get("seen");

  if (isDiscordEnabled(env) && !looksAutomated(request) && !rateLimited()) {
    const payload = buildDownloadEmbed({
      source,
      referer,
      country: request.cf?.country || "",
      city: request.cf?.city || "",
      agent,
      firstSeen: seen === null ? false : seen === "1",
    });
    payload.username = env.DISCORD_BOT_USERNAME || "Vibresia";
    // waitUntil, not await: the redirect goes out whether or not Discord ever
    // answers, and a Discord outage can't turn into a broken download.
    ctx.waitUntil(postDiscord(env, payload));
  }

  return Response.redirect(RELEASE_ZIP, 302);
}

/// Builds the embed for a report from the app. Kept pure for the same reason
/// as `buildDownloadEmbed`: the tests assert on the payload without a network.
export function buildErrorEmbed({ title, message, priority = "high", fields = [] }) {
  const style = STYLES[priority] || STYLES.default;
  return {
    username: undefined, // filled in from env at send time
    embeds: [
      {
        author: { name: "Vibresia app" },
        title: truncate(`${style.emoji} ${title}`, DISCORD_TITLE_LIMIT),
        description: truncate(message ?? "", DISCORD_DESC_LIMIT),
        url: CANONICAL_SITE,
        color: style.color,
        fields: fields
          .filter((f) => f && f.name && f.value)
          .slice(0, 10)
          .map((f) => ({
            name: truncate(f.name, 256),
            value: truncate(f.value, DISCORD_FIELD_LIMIT),
            inline: f.inline !== false,
          })),
        footer: { text: "vibresia.com" },
        timestamp: new Date().toISOString(),
      },
    ],
  };
}

/// `POST /api/notify` — how the Mac app reports problems.
///
/// Authenticated with a shared token so this can't be used as a free posting
/// service for anyone who finds the URL; that token is a Worker secret, and the
/// app ships with it compiled in, which means it should be treated as
/// "public-ish" and rotated if it ever leaks. Discord's own limits and the
/// cooldown above are the real backstop.
async function handleNotify(request, env, ctx) {
  const token = request.headers.get("x-av-token") || "";
  if (!env.NOTIFY_TOKEN || token !== env.NOTIFY_TOKEN) {
    return Response.json({ ok: false, error: "unauthorised" }, { status: 401 });
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return Response.json({ ok: false, error: "bad json" }, { status: 400 });
  }
  // Honeypot: a bot fills in every field it finds. Nothing in the app ever
  // sends this.
  if (body.website) return Response.json({ ok: true });

  const errorsEnabled = env.DISCORD_ERRORS_ENABLED !== "false" && !!env.DISCORD_WEBHOOK_URL;
  if (!errorsEnabled) return Response.json({ ok: true, posted: false });

  if (errorRateLimited()) {
    console.log(`[notify] suppressed: ${body.kind} (cooldown)`);
    return Response.json({ ok: true, posted: false, reason: "rate limited" });
  }

  const payload = buildErrorEmbed({
    title: body.title || "Something went wrong",
    message: body.message || "",
    priority: body.priority || "high",
    fields: Array.isArray(body.fields) ? body.fields : [],
  });
  payload.username = env.DISCORD_BOT_USERNAME || "Vibresia";
  // Fire and forget: the app is waiting on this, and Discord is not on the
  // critical path of anything it is trying to do. Logged anyway, because
  // "we didn't hear about that crash" needs an answer you can grep for.
  ctx.waitUntil(
    postDiscord(env, payload).then((result) => {
      console.log(`[notify] ${result.ok ? "posted" : "FAILED"}: ${body.kind}${result.ok ? "" : ` (${result.error || result.status})`}`);
    })
  );
  return Response.json({ ok: true });
}

function handleHealth(env) {
  return Response.json({
    ok: true,
    notify: env.NOTIFY_TOKEN ? "accepting app reports" : "no NOTIFY_TOKEN (wrangler secret put NOTIFY_TOKEN)",
    discord: isDiscordEnabled(env)
      ? "configured"
      : env.DISCORD_WEBHOOK_URL
        ? "disabled (DISCORD_NOTIFICATIONS_ENABLED is not \"true\")"
        : "missing (set it with: wrangler secret put DISCORD_WEBHOOK_URL)",
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // One canonical URL, at the edge, for everything.
    //
    // Cloudflare's "Always Use HTTPS" setting is the right place for this and
    // should be switched on, but it is a zone setting nobody remembers exists;
    // doing it here means a plain http:// or www:// request can't end up as a
    // second indexable copy of the page whichever way that setting is left.
    // `wrangler dev` proxies every request through miniflare, which rewrites
    // Host to the production hostname from wrangler.toml — so locally this
    // looks exactly like production, over plain http, where both of these
    // redirects would be nonsense and `/download` would loop forever. The
    // original hostname is left behind in a header that only exists locally.
    const proxiedLocally = request.headers.has("mf-original-hostname");
    const isLocal =
      proxiedLocally || /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(request.headers.get("host") || "");
    if (!isLocal) {
      // The old name goes to the new one first, before anything else, so an
      // old http:// link is answered with a single hop to the new https://
      // address rather than a chain through the old one. Path and query
      // are kept, so an old link to a specific page still lands on that
      // page rather than the homepage.
      if (LEGACY_HOSTS.includes(url.hostname)) {
        url.hostname = CANONICAL_HOST;
        url.protocol = "https:";
        return Response.redirect(url.toString(), 301);
      }
      if (url.protocol === "http:") {
        url.protocol = "https:";
        return Response.redirect(url.toString(), 301);
      }
      if (url.hostname === `www.${CANONICAL_HOST}`) {
        url.hostname = CANONICAL_HOST;
        return Response.redirect(url.toString(), 301);
      }
    }

    if (url.pathname === "/download") return handleDownload(request, url, env, ctx);
    if (url.pathname === "/api/notify") return handleNotify(request, env, ctx);
    if (url.pathname === "/api/health") return handleHealth(env);
    // Note: Cloudflare serves a request that matches an existing asset straight
    // from the edge, without invoking this Worker at all (only misses reach it,
    // which is how `x-av-worker` showed up on a 404 and nowhere else). So
    // response headers for the site's own files come from site/_headers, not
    // from here — and `_headers` appends to the asset server's own
    // `cache-control` rather than replacing it, which is why media stays at
    // Cloudflare's default `max-age=0, must-revalidate`. That costs a 304
    // (ETag) round trip per asset on a repeat visit, not a re-download, so
    // it's left alone rather than fought.
    return env.ASSETS.fetch(request);
  },
};