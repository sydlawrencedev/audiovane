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
  lastShareAt = 0;
  sharesThisHour = 0;
  shareHourStartedAt = 0;
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

// Sharing has its own budget again. A person makes a handful of shares in a
// row, so the ceiling is generous for one person and low for a script: what
// is being protected is the daily row-write quota, and burning it would stop
// sharing working for everyone.
const SHARE_MIN_SECONDS_BETWEEN = 1;
const SHARE_MAX_PER_HOUR = 120;
let lastShareAt = 0;
let sharesThisHour = 0;
let shareHourStartedAt = 0;

function shareRateLimited() {
  const now = Date.now();
  if (now - shareHourStartedAt > 3_600_000) {
    shareHourStartedAt = now;
    sharesThisHour = 0;
  }
  if (now - lastShareAt < SHARE_MIN_SECONDS_BETWEEN * 1000) return true;
  if (sharesThisHour >= SHARE_MAX_PER_HOUR) return true;
  lastShareAt = now;
  sharesThisHour += 1;
  return false;
}

// Kept pure and exported so the payload can be asserted on without a network.
// `firstSeen` means "this browser has downloaded before" — the page puts it in
// the link's query string, since a plain link click can't carry a header.
export function buildDownloadEmbed({ source, referer, country, city, agent, firstSeen }) {  const style = STYLES.good;
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

// ------------------------------------------------------------- shared vibescapes
//
// A custom vibescape used to travel as its payload in the query string:
// /share/?d=<base64 of the deflated shader>. That works, but the URL is
// around 370 characters, and it made a 307 redirect on the way in, which
// WhatsApp's link-preview crawler did not follow — so the preview was blank
// and the link looked broken in a chat.
//
// So the payload is stored here and the app shares /s/<id> instead: a short
// URL on this domain that the Worker serves directly, with the payload
// inlined and an og:image that is a picture of this vibescape rather than
// the generic Vibresia one.
//
// D1 rather than Workers KV because KV is eventually consistent. A link
// opened ten seconds after it was shared could reach an edge that had not
// seen the write and 404, which is the whole feature failing at exactly the
// moment it is used. D1 is SQLite-backed and strongly consistent.

// Six characters from an alphabet with no l, 1 or 0 in it — the characters
// people misread when they type one out. About a billion ids.
const SHARE_ID_ALPHABET = "abcdefghijkmnopqrstuvwxyz23456789";
const SHARE_ID_LENGTH = 6;
const SHARE_ID_PATTERN = new RegExp(`^[${SHARE_ID_ALPHABET}]{${SHARE_ID_LENGTH}}$`);

// Caps on what one share can be. The image is the big one: a row is a
// megabyte or two of the free tier's storage per share, and the picture is
// the only part of it that is worth having at a size.
const MAX_PAYLOAD_CHARS = 8192;
const MAX_NAME_CHARS = 120;
const MAX_AUTHOR_CHARS = 120;
const MAX_IMAGE_BYTES = 400 * 1024;
const MAX_KEY_CHARS = 128;

// The key is a hash the app sends: hex, usually. Checking the shape is not
// much, but it is enough to keep anything that is not a key out of the
// database.
const KEY_PATTERN = /^[A-Za-z0-9_-]+$/;

// The payload is base64url of the deflated JSON, so it is base64url
// characters and nothing else. Checking that is not much, but it is enough
// to keep anything that is not a share out of the database.
const PAYLOAD_PATTERN = /^[A-Za-z0-9_-]+$/;

function randomShareId() {
  const bytes = crypto.getRandomValues(new Uint8Array(SHARE_ID_LENGTH));
  let id = "";
  for (const byte of bytes) {
    id += SHARE_ID_ALPHABET[byte % SHARE_ID_ALPHABET.length];
  }
  return id;
}

function isValidShareId(id) {
  return SHARE_ID_PATTERN.test(id);
}

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => {
    switch (c) {
      case "&": return "&amp;";
      case "<": return "&lt;";
      case ">": return "&gt;";
      case '"': return "&quot;";
      default: return "&#39;";
    }
  });
}

/// The page a share is served as.
///
/// The static page at /share/ is the same page, with the payload in the
/// query string. This one has the payload inlined and the metadata rewritten,
/// so a crawler gets a title, a description and a picture for this specific
/// vibescape instead of the generic ones. Crawlers do not run the page's
/// JavaScript, so the metadata has to be right in the HTML itself.
export function buildSharePage(html, { id, payload, name, author, url }) {
  const title = name ? `${name} — Vibresia` : "A vibescape was shared with you — Vibresia";
  const description = author
    ? `A vibescape called “${name}” by ${author}. Open it in Vibresia, free.`
    : "Someone shared a Vibresia vibescape with you. Open it in Vibresia or download the app.";
  const image = `${CANONICAL_SITE}og/${id}.jpg`;

  let out = html;

  // The payload, and which share it is. Injected as a global rather than a
  // query parameter so the URL a recipient sees stays short. The id goes
  // along so the page can put it in the deep link: the app then knows which
  // link the vibescape came from, and can hand the same link back when it
  // is shared on.
  //
  // `</` is escaped because the payload ends up inside a <script> element,
  // and the JSON is the only thing that could close it early.
  const injected = `<script>window.__VIBRESIA_SHARE__ = ${JSON.stringify({ d: payload, id }).replace(/</g, "\\u003c")};</script>`;
  out = out.replace("</head>", `${injected}\n</head>`);

  const swap = (pattern, value) => {
    out = out.replace(pattern, value);
  };
  swap(/<title>[^<]*<\/title>/, `<title>${escapeHtml(title)}</title>`);
  swap(/<link rel="canonical" href="[^"]*">/, `<link rel="canonical" href="${escapeHtml(url)}">`);
  swap(/<meta name="description" content="[^"]*">/, `<meta name="description" content="${escapeHtml(description)}">`);
  swap(/<meta property="og:url" content="[^"]*">/, `<meta property="og:url" content="${escapeHtml(url)}">`);
  swap(/<meta property="og:title" content="[^"]*">/, `<meta property="og:title" content="${escapeHtml(title)}">`);
  swap(/<meta property="og:description" content="[^"]*">/, `<meta property="og:description" content="${escapeHtml(description)}">`);
  swap(/<meta property="og:image" content="[^"]*">/, `<meta property="og:image" content="${escapeHtml(image)}">`);
  swap(/<meta property="og:image:width" content="[^"]*">/, `<meta property="og:image:width" content="1200">`);
  swap(/<meta property="og:image:height" content="[^"]*">/, `<meta property="og:image:height" content="630">`);
  swap(/<meta name="twitter:title" content="[^"]*">/, `<meta name="twitter:title" content="${escapeHtml(title)}">`);
  swap(/<meta name="twitter:description" content="[^"]*">/, `<meta name="twitter:description" content="${escapeHtml(description)}">`);
  swap(/<meta name="twitter:image" content="[^"]*">/, `<meta name="twitter:image" content="${escapeHtml(image)}">`);

  return out;
}

/// Finds a share that already holds this vibescape.
async function findExistingShare(env, { key, payload }) {
  // By key first: that is the app's hash of the content, so it finds the
  // share whoever made it — including one made by somebody else, which is
  // the point: the same vibescape gets the same link.
  if (key) {
    const byKey = await env.SHARES.prepare(
      "SELECT id, image FROM shares WHERE key = ?"
    ).bind(key).first();
    if (byKey) return byKey;
  }
  // By payload, for a share made before the key existed — or by an app
  // version that doesn't send one.
  const byPayload = await env.SHARES.prepare(
    "SELECT id, image FROM shares WHERE payload = ?"
  ).bind(payload).first();
  return byPayload || null;
}

/// `POST /api/share` — the app hands over a vibescape and gets back a short
/// URL for it.
///
/// The token is a speed bump, not a lock: it ships inside the app, so
/// anyone who wants it can read it out of the bundle. What it stops is a
/// script creating shares on this domain to burn the daily write quota,
/// which would break sharing for everyone.
async function handleShareCreate(request, env) {
  const token = request.headers.get("x-av-token") || "";
  if (!env.SHARE_TOKEN || token !== env.SHARE_TOKEN) {
    return Response.json({ ok: false, error: "unauthorised" }, { status: 401 });
  }
  if (shareRateLimited()) {
    return Response.json({ ok: false, error: "slow down" }, { status: 429 });
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return Response.json({ ok: false, error: "bad json" }, { status: 400 });
  }

  const payload = typeof body?.payload === "string" ? body.payload : "";
  const name = typeof body?.name === "string" ? body.name : "";
  const author = typeof body?.author === "string" ? body.author : "";
  const key = typeof body?.key === "string" ? body.key : "";
  if (!payload || payload.length > MAX_PAYLOAD_CHARS || !PAYLOAD_PATTERN.test(payload)) {
    return Response.json({ ok: false, error: "bad payload" }, { status: 400 });
  }
  if (name.length > MAX_NAME_CHARS || author.length > MAX_AUTHOR_CHARS) {
    return Response.json({ ok: false, error: "name too long" }, { status: 400 });
  }
  if (key.length > MAX_KEY_CHARS || (key && !KEY_PATTERN.test(key))) {
    return Response.json({ ok: false, error: "bad key" }, { status: 400 });
  }

  // The picture is optional. Without one the share still works — it just
  // has the generic preview, which is what every custom share used to have.
  let image = null;
  if (typeof body?.image === "string" && body.image.length > 0) {
    let bytes;
    try {
      bytes = Uint8Array.from(atob(body.image), (c) => c.charCodeAt(0));
    } catch {
      return Response.json({ ok: false, error: "bad image" }, { status: 400 });
    }
    if (bytes.length > MAX_IMAGE_BYTES) {
      return Response.json({ ok: false, error: "image too large" }, { status: 400 });
    }
    image = bytes;
  }

  // The same vibescape, the same link.
  //
  // A share used to be made fresh every time, so sharing the same vibescape
  // twice gave you two URLs, and re-sharing one somebody sent you gave you
  // a third. The key is a hash of the vibescape's content, so a share that
  // already exists is found rather than made again.
  const existing = await findExistingShare(env, { key, payload });
  if (existing) {
    // A share made while the picture was missing gets one now, if this
    // request has it. The link stays the same either way.
    if (image && !existing.image) {
      try {
        await env.SHARES.prepare("UPDATE shares SET image = ? WHERE id = ?")
          .bind(image, existing.id).run();
      } catch (error) {
        console.log(`[share] could not add the picture to ${existing.id}: ${error}`);
      }
    }
    return Response.json({
      ok: true,
      id: existing.id,
      url: `${CANONICAL_SITE}s/${existing.id}`,
      imageUrl: existing.image || image ? `${CANONICAL_SITE}og/${existing.id}.jpg` : null,
      existing: true,
    });
  }

  // A handful of tries: the id is six characters from a billion, so a
  // collision is a one-in-a-million thing, but it is a primary key and
  // losing the race should not fail the share.
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const id = randomShareId();
    try {
      await env.SHARES.prepare(
        "INSERT INTO shares (id, payload, name, author, image, key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
      ).bind(id, payload, name, author, image, key || null, Date.now()).run();
      return Response.json({
        ok: true,
        id,
        url: `${CANONICAL_SITE}s/${id}`,
        imageUrl: image ? `${CANONICAL_SITE}og/${id}.jpg` : null,
        existing: false,
      });
    } catch (error) {
      // Two devices sharing the same vibescape at the same moment: one of
      // them won the race, and its link is the link.
      if (String(error).includes("UNIQUE constraint failed")) {
        const raced = await findExistingShare(env, { key, payload });
        if (raced) {
          return Response.json({
            ok: true,
            id: raced.id,
            url: `${CANONICAL_SITE}s/${raced.id}`,
            imageUrl: raced.image || image ? `${CANONICAL_SITE}og/${raced.id}.jpg` : null,
            existing: true,
          });
        }
        continue;
      }
      console.log(`[share] insert failed: ${error}`);
      return Response.json({ ok: false, error: "could not save" }, { status: 500 });
    }
  }
  return Response.json({ ok: false, error: "could not save" }, { status: 500 });
}

/// `GET /s/<id>` — the share itself.
///
/// Served directly rather than redirected to the long form, because a
/// redirect is what WhatsApp's crawler was not following.
async function handleSharePage(request, url, env) {
  const id = url.pathname.slice("/s/".length);
  if (!isValidShareId(id)) return new Response("Not found", { status: 404 });

  const row = await env.SHARES.prepare(
    "SELECT payload, name, author FROM shares WHERE id = ?"
  ).bind(id).first();
  if (!row) return new Response("Not found", { status: 404 });

  // The page itself is a static asset; the Worker pulls it and rewrites the
  // parts that are specific to this share.
  //
  // "/share/" rather than "/share/index.html": the asset service answers the
  // latter with a 307 to the former, and a 3xx is not `ok`, so asking for
  // the file by name looks like a missing asset.
  const asset = await env.ASSETS.fetch(new Request(new URL("/share/", url), request));
  if (!asset.ok) {
    console.log(`[share] could not read the share page: ${asset.status}`);
    return new Response("Not found", { status: 404 });
  }
  const html = await asset.text();

  const page = buildSharePage(html, {
    id,
    payload: row.payload,
    name: row.name,
    author: row.author,
    url: `${CANONICAL_SITE}s/${id}`,
  });

  return new Response(page, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=0, must-revalidate",
    },
  });
}

/// A BLOB column comes back from D1 as an ArrayBuffer in some places and as a
/// plain array of bytes in others, and `new Response()` can only make a body
/// out of the first. So: normalise before responding.
export function toBytes(value) {
  if (value == null) return null;
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  if (Array.isArray(value)) return Uint8Array.from(value);
  return null;
}

/// `GET /og/<id>.jpg` — the picture of the vibescape, for link previews.
///
/// Long-lived, because a share link does not change once it exists and the
/// picture never does either. The id is in the filename, so the cache key is
/// right without asking.
async function handleShareImage(request, url, env) {
  const id = url.pathname.slice("/og/".length).replace(/\.jpg$/, "");
  if (!isValidShareId(id)) return new Response("Not found", { status: 404 });

  const row = await env.SHARES.prepare(
    "SELECT image FROM shares WHERE id = ?"
  ).bind(id).first();
  if (!row) return new Response("Not found", { status: 404 });
  const bytes = toBytes(row.image);
  if (!bytes || bytes.length === 0) return new Response("Not found", { status: 404 });

  return new Response(bytes, {
    headers: {
      "content-type": "image/jpeg",
      "cache-control": "public, max-age=31536000, immutable",
    },
  });
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
    if (url.pathname === "/api/share") return handleShareCreate(request, env);
    if (url.pathname.startsWith("/s/")) return handleSharePage(request, url, env);
    if (url.pathname.startsWith("/og/")) return handleShareImage(request, url, env);
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