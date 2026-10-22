// Vibresia's landing-page Worker.
//
// The site is static, but downloads need a server: that's where we can say
// *someone* downloaded, not just *someone clicked*, and it's where the Discord
// webhook can live without ever touching the browser.
//
// Everything not listed here falls through to the static assets in ./site,
// which still get their `_headers` and `_redirects` treatment on the way out.
//
// It is also the public MCP server, at /mcp — so that an agent in a chat
// window can write a vibescape and hand somebody a link to it.
//
// The Discord side follows delphina's pattern (plain webhook, embed with a
// colour per priority, never let a notification failure break the user's
// path) and adds the three things delphina's own notifications are missing
// because they run inline in a request: a timeout, one retry, and
// `ctx.waitUntil` so Discord can never delay a download.

import { handleMcp } from "./mcp.js";

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

// Apple's link previews.
//
// When somebody pastes a link into a message, the phone fetches it to draw
// the card — and it fetches the *download* link too, because that is what
// the card says to do. The user agent is the giveaway: Safari/604.1 is
// Apple's preview fetcher, and no real Safari sends it.
const LINK_PREVIEW = /Safari\/604\.1/;

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

  // Whether this is somebody downloading the app, or something else
  // touching the link.
  //
  // A HEAD request is a check, not a download — a link checker, or a
  // "does this still work?" probe. And Apple's link previews fetch the
  // download link to draw the card somebody sees in a message, which is
  // somebody else reading a link rather than installing anything.
  //
  // The redirect still happens either way: a preview fetcher wants the zip
  // and a head wants the headers, and neither is a person who needs
  // telling about.
  const isPreview = LINK_PREVIEW.test(agent);
  const isProbe = request.method === "HEAD";
  const counted = !looksAutomated(request) && !isPreview && !isProbe;

  if (counted) {
    // The count that doesn't depend on anybody's JavaScript running.
    //
    // The site sends a download_clicked event, but that is a lower bound:
    // an ad blocker stops it, and a link preview never runs the page's
    // JavaScript at all. This one is fired by the server, after the
    // filters, so it counts the downloads that actually happened.
    ctx.waitUntil(postDownloadEvent(env, {
      source,
      referer,
      country: request.cf?.country || "",
      city: request.cf?.city || "",
      seen: seen === null ? false : seen === "1",
    }));
  }

  if (isDiscordEnabled(env) && counted && !rateLimited()) {
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

/// A download, counted on the server.
///
/// The public project key, which is in the page's HTML anyway — this is a
/// write-only key, and the project is the same one the site and the app
/// report to. Not a personal API key: that would be a credential in the
/// Worker, and a download count is not worth one.
///
/// The distinct id is a constant, and that is a decision rather than an
/// oversight. The site knows which visitor downloaded, but the Worker does
/// not: the browser's id is in its local storage, and putting it in a
/// download link would hand it to every service that fetched the link. So
/// this event counts downloads, and the count of people comes from the site.
function postDownloadEvent(env, { source, referer, country, city, seen }) {
  const key = env.POSTHOG_KEY;
  if (!key) return Promise.resolve();
  const host = (env.POSTHOG_HOST || "https://us.i.posthog.com").replace(/\/+$/, "");
  const event = {
    api_key: key,
    event: "download_requested",
    distinct_id: "downloads",
    properties: {
      surface: "web",
      $lib: "vibresia-web",
      source,
      referer,
      country,
      city,
      seen,
    },
    timestamp: new Date().toISOString(),
  };
  return fetch(`${host}/batch/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify([event]),
  }).then((response) => {
    if (!response.ok) {
      console.log(`[download] the event was refused: ${response.status}`);
    }
  }).catch((error) => {
    // A download that happened is a download that happened, whatever the
    // analytics said about it.
    console.log(`[download] could not record the event: ${error}`);
  });
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
export function buildSharePage(html, { id, payload, name, author, url, hasImage = true }) {
  const title = name ? `${name} — Vibresia` : "A vibescape was shared with you — Vibresia";
  const description = author
    ? `A vibescape called “${name}” by ${author}. Open it in Vibresia, free.`
    : "Someone shared a Vibresia vibescape with you. Open it in Vibresia or download the app.";
  // A share with no picture of its own gets the general Vibresia one, rather
  // than a link to a picture that is not there.
  const image = hasImage ? `${CANONICAL_SITE}og/${id}.jpg` : `${CANONICAL_SITE}media/share.jpg`;

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
    // A function, not a string: `String.replace` treats `$&` and `` $` `` in a
    // string replacement as patterns, and the replacement here is the name
    // somebody typed. A name with a dollar in it would otherwise paste the
    // page's own markup into the middle of the title.
    out = out.replace(pattern, () => value);
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
async function findExistingShare(env, { key, payloadHash, payload }) {
  // By key first: that is the app's hash of the content, so it finds the
  // share whoever made it — including one made by somebody else, which is
  // the point: the same vibescape gets the same link.
  if (key) {
    const byKey = await query(
      env,
      "SELECT id, image FROM shares WHERE key = ?",
      [key],
    );
    if (byKey) return byKey;
  }
  // By payload hash, for a share made before the key existed — or by an app
  // version that doesn't send one. The hash rather than the payload itself:
  // a payload is too long to index, and looking for it by value means
  // reading every row in the table, which D1 charges for.
  if (payloadHash) {
    const byHash = await query(
      env,
      "SELECT id, image FROM shares WHERE payload_hash = ?",
      [payloadHash],
    );
    if (byHash) return byHash;
  }
  // Last resort: the payload itself. Only for rows made before the hash
  // column existed, which is a handful of rows for the life of the site.
  const byPayload = await query(
    env,
    "SELECT id, image FROM shares WHERE payload = ?",
    [payload],
  );
  return byPayload || null;
}

/// Runs a query, treating a failure as "not found".
///
/// The columns this asks about are added by a migration. If the migration
/// hasn't been applied yet, the query throws, and a share that can still be
/// made is better than no sharing at all.
async function query(env, sql, bindings) {
  try {
    return await env.SHARES.prepare(sql).bind(...bindings).first();
  } catch (error) {
    console.log(`[share] query failed (${sql.split(" ").slice(0, 3).join(" ")}…): ${error}`);
    return null;
  }
}

/// Gives a share its picture, if it hasn't got one.
async function ensureImage(env, row, image) {
  if (!image || row.image) return;
  try {
    await env.SHARES.prepare("UPDATE shares SET image = ? WHERE id = ?")
      .bind(image, row.id).run();
    row.image = image;
  } catch (error) {
    console.log(`[share] could not add the picture to ${row.id}: ${error}`);
  }
}

/// The hash of a payload, for finding a share that holds it.
async function hashPayload(payload) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(payload));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/// The share a vibescape is looked up by, and whether it is in the public
/// gallery.
async function insertShare(env, { id, payload, payloadHash, name, author, image, key, isPublic }) {
  const created = Date.now();
  try {
    await env.SHARES.prepare(
      "INSERT INTO shares (id, payload, name, author, image, key, payload_hash, is_public, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
    ).bind(id, payload, name, author, image, key || null, payloadHash || null, isPublic, created).run();
  } catch (error) {
    if (!String(error).includes("no such column")) throw error;
    await env.SHARES.prepare(
      "INSERT INTO shares (id, payload, name, author, image, created_at) VALUES (?, ?, ?, ?, ?, ?)"
    ).bind(id, payload, name, author, image, created).run();
  }
}

/// Whether a share is in the public gallery.
///
/// The app asks, in the share sheet: there is a tickbox, on by default, and
/// it says the name and the author are public. A share made before the
/// gallery existed is not in it — it was never offered the choice.
async function setPublic(env, id, isPublic) {
  try {
    await env.SHARES.prepare("UPDATE shares SET is_public = ? WHERE id = ?")
      .bind(isPublic ? 1 : 0, id).run();
  } catch (error) {
    // A database without the column yet: the share is still a share, it just
    // isn't in the gallery.
    console.log(`[share] could not set the gallery flag on ${id}: ${error}`);
  }
}

/// Removes a share.
///
/// Used when a share is replaced — somebody changed their name, which makes a
/// different vibescape, which gets a different link. The old one goes with
/// it, so the gallery does not fill up with every version of the same
/// vibescape.
async function deleteShare(env, id) {
  if (!isValidShareId(id)) return false;
  try {
    const result = await env.SHARES.prepare("DELETE FROM shares WHERE id = ?")
      .bind(id).run();
    return (result?.meta?.changes ?? 0) > 0;
  } catch (error) {
    console.log(`[share] could not delete ${id}: ${error}`);
    return false;
  }
}

/// A share's details, for the app to check what it has.
///
/// The gallery flag in particular: the tickbox in the share sheet has to
/// show what is true, not what it was set to when the sheet opened.
async function handleShareGet(request, url, env) {
  const id = url.pathname.slice("/api/share/".length);
  if (!isValidShareId(id)) return Response.json({ ok: false, error: "no such share" }, { status: 404 });
  const row = await env.SHARES.prepare(
    "SELECT id, name, author, is_public, created_at FROM shares WHERE id = ?"
  ).bind(id).first();
  if (!row) return Response.json({ ok: false, error: "no such share" }, { status: 404 });
  return Response.json({
    ok: true,
    id: row.id,
    name: row.name || "",
    author: row.author || "",
    public: row.is_public === 1,
    sharedAt: row.created_at,
  });
}

/// `PATCH /api/share/<id>` — puts a share in the public gallery, or takes it
/// out.
///
/// The tickbox in the app's share sheet has to do something. It used to be
/// read only when a share was made, so a share that was already made kept
/// whatever it was made with — and unticking it did nothing at all.
async function handleSharePatch(request, url, env) {
  const token = request.headers.get("x-av-token") || "";
  if (!env.SHARE_TOKEN || token !== env.SHARE_TOKEN) {
    return Response.json({ ok: false, error: "unauthorised" }, { status: 401 });
  }
  const id = url.pathname.slice("/api/share/".length);
  if (!isValidShareId(id)) return Response.json({ ok: false, error: "no such share" }, { status: 404 });

  let body;
  try {
    body = await request.json();
  } catch {
    return Response.json({ ok: false, error: "bad json" }, { status: 400 });
  }
  if (typeof body?.public !== "boolean") {
    return Response.json({ ok: false, error: "public must be true or false" }, { status: 400 });
  }
  await setPublic(env, id, body.public);
  return Response.json({ ok: true, id, public: body.public });
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
  // The share this one replaces, if it replaces one. Somebody changed their
  // name, which makes a different vibescape, which gets a different link —
  // and the old one goes, so the gallery does not fill up with every version
  // of the same vibescape.
  const replaces = typeof body?.replaces === "string" ? body.replaces : "";
  // Whether it goes in the public gallery. The app asks in the share sheet,
  // and says there that the name and the author are public.
  const isPublic = body?.public === true;
  if (!payload || payload.length > MAX_PAYLOAD_CHARS || !PAYLOAD_PATTERN.test(payload)) {
    return Response.json({ ok: false, error: "bad payload" }, { status: 400 });
  }
  if (name.length > MAX_NAME_CHARS || author.length > MAX_AUTHOR_CHARS) {
    return Response.json({ ok: false, error: "name too long" }, { status: 400 });
  }
  if (key.length > MAX_KEY_CHARS || (key && !KEY_PATTERN.test(key))) {
    return Response.json({ ok: false, error: "bad key" }, { status: 400 });
  }
  if (replaces && !isValidShareId(replaces)) {
    return Response.json({ ok: false, error: "bad replaces id" }, { status: 400 });
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
  const payloadHash = await hashPayload(payload);
  const existing = await findExistingShare(env, { key, payloadHash, payload });
  if (existing) {
    // A share made while the picture was missing gets one now, if this
    // request has it. The link stays the same either way.
    await ensureImage(env, existing, image);
    // And the gallery follows the tickbox, so a share that was kept out of
    // it can be put in by sharing it again.
    await setPublic(env, existing.id, isPublic);
    return Response.json({
      ok: true,
      id: existing.id,
      url: `${CANONICAL_SITE}s/${existing.id}`,
      imageUrl: existing.image ? `${CANONICAL_SITE}og/${existing.id}.jpg` : null,
      public: isPublic,
      existing: true,
    });
  }

  // A handful of tries: the id is six characters from a billion, so a
  // collision is a one-in-a-million thing, but it is a primary key and
  // losing the race should not fail the share.
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const id = randomShareId();
    try {
      await insertShare(env, { id, payload, payloadHash, name, author, image, key, isPublic });
      // The share this one replaces goes now that the new one is in place —
      // and only now, and only if it is a different share. Replacing a share
      // with itself would delete the row that was just written.
      if (replaces && replaces !== id) {
        await deleteShare(env, replaces);
      }
      return Response.json({
        ok: true,
        id,
        url: `${CANONICAL_SITE}s/${id}`,
        imageUrl: image ? `${CANONICAL_SITE}og/${id}.jpg` : null,
        public: isPublic,
        existing: false,
      });
    } catch (error) {
      // Two devices sharing the same vibescape at the same moment: one of
      // them won the race, and its link is the link.
      if (String(error).includes("UNIQUE constraint failed")) {
        const raced = await findExistingShare(env, { key, payloadHash, payload });
        if (raced) {
          // The winner may have been made without a picture — by an older
          // app, or by a render that came back empty. This one has a
          // picture, so it goes in.
          await ensureImage(env, raced, image);
          await setPublic(env, raced.id, isPublic);
          return Response.json({
            ok: true,
            id: raced.id,
            url: `${CANONICAL_SITE}s/${raced.id}`,
            imageUrl: raced.image ? `${CANONICAL_SITE}og/${raced.id}.jpg` : null,
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
    "SELECT payload, name, author, CASE WHEN image IS NULL THEN 0 ELSE 1 END AS has_image FROM shares WHERE id = ?"
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
    // A share made by an agent has no picture, because the server cannot
    // draw one. Pointing og:image at a picture that is not there would give
    // the link preview a broken image, so it gets the general one instead.
    hasImage: row.has_image === 1,
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

/// A path on this site, as an absolute URL.
///
/// The site ends with a slash and the paths start with one, so joining them
/// as they are makes a double slash — which works, and looks like a mistake.
function absolute(path) {
  return `${CANONICAL_SITE.replace(/\/$/, "")}${path}`;
}

/// The public gallery: the shares that were ticked into it.
///
/// A share is a link anybody can open. The gallery is different — it lists
/// them, so anything in it is findable by anybody at all, and the name and
/// the author on it are public.
///
/// `all` is for the admin, who needs the ones that are hidden as well as the
/// ones that are not.
async function galleryRows(env, { all = false } = {}) {
  try {
    // Whether the share has a picture, rather than the picture: the column
    // is a blob of up to 400KB, and reading all of them to find out whether
    // they are there would cost more than the gallery is worth.
    const where = all ? "" : "WHERE is_public = 1";
    const result = await env.SHARES.prepare(
      `SELECT id, name, author, created_at, is_public,
              CASE WHEN image IS NULL THEN 0 ELSE 1 END AS has_image
       FROM shares ${where} ORDER BY created_at DESC LIMIT 200`
    ).all();
    return result.results || [];
  } catch (error) {
    // A database without the column yet: no gallery, rather than an error.
    console.log(`[gallery] could not read the gallery: ${error}`);
    return [];
  }
}

/// The built-in vibescapes, from the manifest the share pages are made from.
///
/// They are in the gallery because they are shareable: each one has a page
/// of its own, with a picture and a video, that anybody can open.
async function builtinRows(env, url) {
  try {
    const asset = await env.ASSETS.fetch(
      new Request(new URL("/share/manifest.json", url)));
    if (!asset.ok) return [];
    const manifest = JSON.parse(await asset.text());
    const builtins = Array.isArray(manifest?.built_ins) ? manifest.built_ins : [];
    return builtins
      .filter((entry) => entry && typeof entry.slug === "string")
      .map((entry) => ({
        slug: entry.slug,
        name: typeof entry.title === "string" ? entry.title : entry.slug,
        // The day it first existed, so the gallery can sort it against the
        // shares people have made.
        date: typeof entry.date === "string" ? entry.date : "",
      }));
  } catch (error) {
    console.log(`[gallery] could not read the manifest: ${error}`);
    return [];
  }
}

/// The whole gallery: the built-ins and the shares people made, in one list,
/// newest first.
///
/// The built-ins are dated by the day they first appeared and the shares by
/// the day they were made, so the two can be sorted against each other.
async function galleryItems(env, url) {
  const rows = await galleryRows(env);
  const builtins = await builtinRows(env, url);

  const items = builtins.map((entry) => ({
    // Midnight, so a built-in and a share made on the same day are in the
    // order they were made.
    at: Date.parse(`${entry.date}T00:00:00Z`) || 0,
    id: entry.slug,
    name: entry.name,
    author: "Minith Labs",
    url: `/share/${entry.slug}`,
    // The clean still, not the share graphic: the framed one has a title and
    // a credit painted on it, which is the page's business and not the
    // gallery's.
    image: `/media/modes/${entry.slug}.jpg`,
    builtin: true,
  }));

  for (const row of rows) {
    items.push({
      at: row.created_at || 0,
      id: row.id,
      name: row.name || "",
      author: row.author || "",
      url: `/s/${row.id}`,
      // A share with no picture of its own gets the general one, rather than
      // a broken image on a page about pictures.
      image: row.has_image ? `/og/${row.id}.jpg` : "/media/share.jpg",
      builtin: false,
    });
  }

  items.sort((a, b) => b.at - a.at);
  return items;
}

/// `GET /api/admin/shares` — every share, for the admin page.
///
/// The token here is not the share token. That one ships inside the app, so
/// anybody can read it out of the bundle, and it is only a speed bump against
/// a script filling the site up. This one is a Worker secret that never
/// leaves the server, and it is the only thing between the public internet
/// and the gallery.
async function handleAdminList(request, env) {
  if (!isAdmin(request, env)) {
    return Response.json({ ok: false, error: "unauthorised" }, { status: 401 });
  }
  const rows = await galleryRows(env, { all: true });
  return Response.json({
    ok: true,
    shares: rows.map((row) => ({
      id: row.id,
      name: row.name || "",
      author: row.author || "",
      url: `${CANONICAL_SITE}s/${row.id}`,
      imageUrl: row.has_image ? `${CANONICAL_SITE}og/${row.id}.jpg` : null,
      inGallery: row.is_public === 1,
      hasImage: row.has_image === 1,
      sharedAt: row.created_at,
    })),
  });
}

/// `POST /api/admin/shares/<id>` — hide a share, put it back, or delete it.
///
/// Hiding takes it out of the gallery and leaves the link working, which is
/// the one to reach for when a share is fine but should not be listed.
/// Deleting takes the row, and the link with it: the picture, the name and
/// the vibescape itself all go.
async function handleAdminAction(request, url, env) {
  if (!isAdmin(request, env)) {
    return Response.json({ ok: false, error: "unauthorised" }, { status: 401 });
  }
  const id = url.pathname.slice("/api/admin/shares/".length);
  if (!isValidShareId(id)) return Response.json({ ok: false, error: "no such share" }, { status: 404 });

  let body;
  try {
    body = await request.json();
  } catch {
    return Response.json({ ok: false, error: "bad json" }, { status: 400 });
  }
  const action = typeof body?.action === "string" ? body.action : "";

  if (action === "hide" || action === "show") {
    await setPublic(env, id, action === "show");
    return Response.json({ ok: true, id, inGallery: action === "show" });
  }
  if (action === "delete") {
    const gone = await deleteShare(env, id);
    if (!gone) return Response.json({ ok: false, error: "no such share" }, { status: 404 });
    return Response.json({ ok: true, id, deleted: true });
  }
  return Response.json({ ok: false, error: "unknown action" }, { status: 400 });
}

/// Whether the request carries the admin token.
function isAdmin(request, env) {
  const token = request.headers.get("x-av-admin-token") || "";
  return !!env.ADMIN_TOKEN && token === env.ADMIN_TOKEN;
}

/// `GET /api/gallery` — the gallery, as JSON.
async function handleGalleryAPI(request, env, url) {
  const items = await galleryItems(env, url);
  return Response.json({
    ok: true,
    vibescapes: items.map((item) => ({
      id: item.id,
      name: item.name,
      author: item.author,
      url: absolute(item.url),
      imageUrl: absolute(item.image),
      builtin: item.builtin,
      sharedAt: item.at,
    })),
  });
}

/// `GET /vibescapes` — the gallery, as a page.
///
/// The cards are built here rather than in the browser: the page is a list of
/// things, and a list that only exists once the JavaScript has run is a list
/// a crawler never sees.
async function handleGalleryPage(request, url, env) {
  const items = await galleryItems(env, url);

  // "/vibescapes" rather than "/vibescapes.html": the asset service answers
  // a file with a ".html" on the end with a redirect, and a redirect is not
  // `ok` — so asking for the file by name looks like a missing asset.
  const asset = await env.ASSETS.fetch(new Request(new URL("/vibescapes", url), request));
  if (!asset.ok) {
    console.log(`[gallery] could not read the gallery page: ${asset.status}`);
    return new Response("Not found", { status: 404 });
  }
  const html = await asset.text();

  const cards = items.map((item) => {
    const name = escapeHtml(item.name || "A vibescape");
    const author = escapeHtml(item.author || "");
    const id = escapeHtml(item.id);
    return `      <a class="card" href="${escapeHtml(item.url)}">
        <img src="${escapeHtml(item.image)}" alt="${name}" loading="lazy" width="1200" height="630">
        <span class="card-name">${name}</span>
        <span class="card-by">${author ? `by ${author}` : ""}</span>
      </a>`;
  }).join("\n");

  const empty = items.length === 0
    ? `      <p class="gallery-empty">Nothing here yet. Share a vibescape from the app and tick it into the gallery.</p>`
    : "";

  const shared = items.filter((item) => !item.builtin).length;
  const summary = [
    items.length ? `${items.length} in all` : "",
    shared ? `${shared} shared by people` : "",
  ].filter(Boolean).join(", ");

  const page = html
    .replace("<!-- gallery:cards -->", cards + "\n" + empty)
    .replace("<!-- gallery:count -->", summary || "nothing here yet");

  return new Response(page, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=0, must-revalidate",
    },
  });
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
    if (url.pathname === "/mcp") return handleMcp(request, env);
    // The MCP registry's discovery file. It is also how the domain is proved
    // to own the server it claims to.
    if (url.pathname === "/.well-known/mcp.json") {
      return Response.json({
        $schema: "https://static.modelcontextprotocol.io/schemas/2025-07-09/server.schema.json",
        name: "com.minithlabs.vibresia",
        description: "Write music visualisations — GLSL vibescapes that draw themselves from the music — and share them as links that play in a browser.",
        status: "active",
        version: "1.0.0",
        repository: {
          url: "https://github.com/sydlawrencedev/vibresia",
          source: "github",
          id: "sydlawrencedev/vibresia",
        },
        websiteUrl: "https://vibresia.com",
        packages: [
          {
            registryType: "remote",
            version: "1.0.0",
            transport: { type: "streamable-http" },
            remote: { url: `${CANONICAL_SITE}mcp` },
            runtimeHint: "node",
          },
        ],
      }, {
        headers: { "cache-control": "public, max-age=3600" },
      });
    }
    if (url.pathname.startsWith("/api/share/")) {
      if (request.method === "PATCH") return handleSharePatch(request, url, env);
      return handleShareGet(request, url, env);
    }
    if (url.pathname === "/api/gallery") return handleGalleryAPI(request, env, url);
    if (url.pathname === "/api/admin/shares") return handleAdminList(request, env);
    if (url.pathname.startsWith("/api/admin/shares/")) {
      return handleAdminAction(request, url, env);
    }
    if (url.pathname === "/vibescapes") return handleGalleryPage(request, url, env);
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