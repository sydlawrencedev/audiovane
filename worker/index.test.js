// Tests for the Worker: node --test worker/
//
// The Discord POST is captured by replacing global fetch, so nothing here
// touches the network or needs a webhook — the same reason delphina mocks
// `https` in its notification tests. Keeping the payload builder pure is what
// makes that possible.

import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";

import worker, { buildDownloadEmbed, buildErrorEmbed, isDiscordEnabled, resetRateLimiter } from "./index.js";

const RELEASE_ZIP =
  "https://github.com/sydlawrencedev/vibresia/releases/latest/download/Vibresia.zip";

function makeEnv(overrides = {}) {
  return {
    ASSETS: { fetch: async () => new Response("asset", { status: 200 }) },
    DISCORD_WEBHOOK_URL: "https://discord.com/api/webhooks/1/token",
    DISCORD_NOTIFICATIONS_ENABLED: "true",
    DISCORD_BOT_USERNAME: "Vibresia",
    ...overrides,
  };
}

/** Runs the worker with fetch stubbed, returning the response and every POST. */
async function run(url, { env = makeEnv(), headers = {}, cf = {}, method = "GET", body } = {}) {
  const posts = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (target, init) => {
    posts.push({ url: String(target), body: JSON.parse(init.body) });
    // 204 is what a Discord webhook actually answers, and it carries no body.
    return new Response(null, { status: 204 });
  };
  const request = new Request(url, { method, headers, body });
  Object.defineProperty(request, "cf", { value: cf });
  const waits = [];
  const ctx = { waitUntil: (promise) => waits.push(promise) };
  try {
    const response = await worker.fetch(request, env, ctx);
    await Promise.all(waits); // the Discord post is fire-and-forget
    return { response, posts };
  } finally {
    globalThis.fetch = realFetch;
  }
}

// The debounce is per-isolate module state on purpose; the tests share one
// process, so each case starts from a clean slate.
beforeEach(resetRateLimiter);

const BROWSER_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15";

test("download redirects to the latest release", async () => {
  const { response, posts } = await run("https://vibresia.com/download?src=hero&seen=0", {
    headers: { "user-agent": BROWSER_UA, referer: "https://vibresia.com/" },
  });
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), RELEASE_ZIP);
  assert.equal(posts.length, 1);
});

test("the notification says who, where and whether it is a repeat", async () => {
  const { posts } = await run("https://vibresia.com/download?src=hero&seen=1", {
    headers: { "user-agent": BROWSER_UA, referer: "https://vibresia.com/?x=1" },
    cf: { country: "GB", city: "Alton" },
  });
  const embed = posts[0].body.embeds[0];
  const fields = Object.fromEntries(embed.fields.map((f) => [f.name, f.value]));
  assert.match(embed.title, /downloaded Vibresia/);
  assert.equal(posts[0].body.username, "Vibresia");
  assert.equal(fields.Source, "hero");
  assert.equal(fields.Where, "Alton, GB");
  assert.match(fields["Seen before"], /has downloaded before/);
  assert.equal(embed.url, RELEASE_ZIP);
});

test("a first download says so, and a missing src is not invented", async () => {
  const { posts } = await run("https://vibresia.com/download", {
    headers: { "user-agent": BROWSER_UA },
  });
  const embed = posts[0].body.embeds[0];
  const names = embed.fields.map((f) => f.name);
  assert.ok(!names.includes("Source"));
  assert.equal(
    embed.fields.find((f) => f.name === "Seen before").value,
    "no — first download from this browser"
  );
});

test("a double-clicked button only notifies once", async () => {
  const first = await run("https://vibresia.com/download?src=hero&seen=0", {
    headers: { "user-agent": BROWSER_UA },
  });
  const second = await run("https://vibresia.com/download?src=hero&seen=0", {
    headers: { "user-agent": BROWSER_UA },
  });
  assert.equal(first.posts.length, 1);
  assert.equal(second.posts.length, 0, "second click inside the window is dropped");
  assert.equal(second.response.status, 302, "but the file still downloads");
});

test("crawlers and link previewers don't generate notifications", async () => {
  for (const agent of [
    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "curl/8.4.0",
    "Slackbot-LinkExpanding 1.0",
    "WhatsApp/2.23.20",
  ]) {
    const { response, posts } = await run("https://vibresia.com/download", {
      headers: { "user-agent": agent },
    });
    assert.equal(response.status, 302, `${agent} still gets the file`);
    assert.equal(posts.length, 0, `${agent} should not post`);
  }
});

test("no webhook configured means a silent download, not an error", async () => {
  const { response, posts } = await run("https://vibresia.com/download", {
    env: makeEnv({ DISCORD_WEBHOOK_URL: "", DISCORD_NOTIFICATIONS_ENABLED: "true" }),
    headers: { "user-agent": BROWSER_UA },
  });
  assert.equal(response.status, 302);
  assert.equal(posts.length, 0);
});

test("the switch really is off when it says it is", async () => {
  const env = makeEnv({ DISCORD_NOTIFICATIONS_ENABLED: "false" });
  assert.equal(isDiscordEnabled(env), false);
  const { response, posts } = await run("https://vibresia.com/download", {
    env,
    headers: { "user-agent": BROWSER_UA },
  });
  assert.equal(response.status, 302);
  assert.equal(posts.length, 0);
});

test("a Discord outage never breaks the download", async () => {
  const realFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    throw new Error("ECONNREFUSED");
  };
  const request = new Request("https://vibresia.com/download", {
    headers: { "user-agent": BROWSER_UA },
  });
  const waits = [];
  try {
    const response = await worker.fetch(request, makeEnv(), { waitUntil: (p) => waits.push(p) });
    assert.equal(response.status, 302);
    assert.equal(response.headers.get("location"), RELEASE_ZIP);
    await Promise.all(waits); // resolves rather than rejecting: waitUntil would log an unhandled error
    assert.equal(calls, 2, "one retry, then it gives up quietly");
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("http and www are redirected to the canonical URL", async () => {
  const http = await run("http://vibresia.com/");
  assert.equal(http.response.status, 301);
  assert.equal(http.response.headers.get("location"), "https://vibresia.com/");

  const www = await run("https://www.vibresia.com/download?src=hero");
  assert.equal(www.response.status, 301);
  assert.equal(www.response.headers.get("location"), "https://vibresia.com/download?src=hero");
});

test("the old hostname redirects to the new one, keeping the path", async () => {
  // The old install command and any old link in someone's post have to
  // keep working, and land on the page they asked for rather than the
  // homepage.
  const install = await run("https://audiovane.minithlabs.com/install.sh");
  assert.equal(install.response.status, 301);
  assert.equal(
    install.response.headers.get("location"),
    "https://vibresia.com/install.sh"
  );

  const download = await run("https://audiovane.minithlabs.com/download?src=hero");
  assert.equal(download.response.status, 301);
  assert.equal(
    download.response.headers.get("location"),
    "https://vibresia.com/download?src=hero"
  );

  // An old plain-http link goes straight to the new address, in one hop.
  const plain = await run("http://audiovane.minithlabs.com/");
  assert.equal(plain.response.status, 301);
  assert.equal(plain.response.headers.get("location"), "https://vibresia.com/");
});

test("local dev is left alone", async () => {
  // `wrangler dev` rewrites Host to the production hostname over plain http.
  // Redirecting there would loop /download back onto itself forever, so the
  // miniflare proxy's header is what marks a request as local.
  const { response, posts } = await run("http://vibresia.com/download?src=hero&seen=0", {
    headers: { "user-agent": BROWSER_UA, "mf-original-hostname": "127.0.0.1:8787" },
  });
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), RELEASE_ZIP);
  assert.equal(posts.length, 1);

  const onLocalhost = await run("http://localhost:8787/", { headers: { host: "localhost:8787" } });
  assert.equal(onLocalhost.response.status, 200);
});

test("everything else falls through to the static assets", async () => {
  const { response, posts } = await run("https://vibresia.com/index.html");
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "asset");
  assert.equal(posts.length, 0);
});

test("the app can report a problem, but only with the token", async () => {
  const body = {
    kind: "audio_error",
    title: "Audio source failed: denied",
    message: "Failed to create process tap (OSStatus -536905213).",
    priority: "urgent",
    fields: [{ name: "mode", value: "band" }],
  };
  const env = makeEnv({ NOTIFY_TOKEN: "s3cret" });

  const wrong = await run("https://vibresia.com/api/notify", {
    env,
    method: "POST",
    body: JSON.stringify(body),
    headers: { "content-type": "application/json", "x-av-token": "nope" },
  });
  assert.equal(wrong.response.status, 401, "a bad token gets nothing");
  assert.equal(wrong.posts.length, 0);

  const ok = await run("https://vibresia.com/api/notify", {
    env,
    method: "POST",
    body: JSON.stringify(body),
    headers: { "content-type": "application/json", "x-av-token": "s3cret" },
  });
  assert.equal(ok.response.status, 200);
});

test("an error report reaches Discord shaped like an error", async () => {
  const body = JSON.stringify({
    kind: "audio_error",
    title: "Audio source failed: system audio failed",
    message: "Failed to create process tap.",
    priority: "urgent",
    fields: [{ name: "mode", value: "band" }, { name: "genre", value: "Jazz" }],
  });
  const posts = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (target, init) => {
    posts.push({ url: String(target), body: JSON.parse(init.body) });
    return new Response(null, { status: 204 });
  };
  const request = new Request("https://vibresia.com/api/notify", {
    method: "POST",
    headers: { "content-type": "application/json", "x-av-token": "s3cret" },
    body,
  });
  const waits = [];
  try {
    const response = await worker.fetch(request, makeEnv({ NOTIFY_TOKEN: "s3cret" }), {
      waitUntil: (p) => waits.push(p),
    });
    await Promise.all(waits);
    assert.equal(response.status, 200);
    const embed = posts[0].body.embeds[0];
    assert.equal(embed.color, 0xe74c3c, "urgent is red");
    assert.match(embed.title, /Audio source failed/);
    assert.deepEqual(embed.fields.map((f) => f.name), ["mode", "genre"]);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("reports stop at one a minute, so a broken install can't flood the channel", async () => {
  const headers = { "content-type": "application/json", "x-av-token": "s3cret" };
  const body = JSON.stringify({ kind: "audio_error", title: "still broken", message: "again" });
  const env = makeEnv({ NOTIFY_TOKEN: "s3cret" });
  const send = () => run("https://vibresia.com/api/notify", { env, method: "POST", headers, body });

  const first = await send();
  assert.equal(first.posts.length, 1);
  for (let i = 0; i < 4; i++) await send(); // inside the cooldown
  const last = await send();
  assert.equal(last.posts.length, 0);
});

test("a bot filling in the honeypot gets a polite nothing", async () => {
  const headers = { "content-type": "application/json", "x-av-token": "s3cret" };
  const request = new Request("https://vibresia.com/api/notify", {
    method: "POST",
    headers,
    body: JSON.stringify({ title: "buy followers", message: "cheap links", website: "http://spam" }),
  });
  const posts = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (t, i) => { posts.push(i); return new Response(null, { status: 204 }); };
  try {
    const response = await worker.fetch(request, makeEnv({ NOTIFY_TOKEN: "s3cret" }), {
      waitUntil: () => {},
    });
    assert.equal(response.status, 200);
    assert.equal(posts.length, 0);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("errors can be switched off without taking downloads with them", async () => {
  const headers = { "content-type": "application/json", "x-av-token": "s3cret" };
  const { response, posts } = await run("https://vibresia.com/api/notify", {
    env: makeEnv({ NOTIFY_TOKEN: "s3cret", DISCORD_ERRORS_ENABLED: "false" }),
    method: "POST",
    headers,
    body: JSON.stringify({ kind: "audio_error", title: "quiet please", message: "" }),
  });
  assert.equal(response.status, 200);
  assert.equal(posts.length, 0);

  const dl = await run("https://vibresia.com/download?src=hero&seen=0", {
    env: makeEnv({ DISCORD_ERRORS_ENABLED: "false" }),
    headers: { "user-agent": BROWSER_UA },
  });
  assert.equal(dl.posts.length, 1, "downloads still notify");
});

test("a long report is trimmed to what Discord accepts", () => {
  const embed = buildErrorEmbed({
    title: "t".repeat(400),
    message: "m".repeat(6000),
    fields: Array.from({ length: 30 }, (_, i) => ({ name: `f${i}`, value: "v".repeat(2000) })),
  });
  assert.ok(embed.embeds[0].title.length <= 256);
  assert.ok(embed.embeds[0].description.length <= 4096);
  assert.ok(embed.embeds[0].fields.length <= 10);
  for (const f of embed.embeds[0].fields) assert.ok(f.value.length <= 1024);
});

test("health reports which state the webhook is in", async () => {
  const ok = await run("https://vibresia.com/api/health", {
    env: makeEnv({ NOTIFY_TOKEN: "s3cret" }),
  });
  assert.deepEqual(await ok.response.json(), {
    ok: true,
    notify: "accepting app reports",
    discord: "configured",
  });

  const noToken = await run("https://vibresia.com/api/health");
  assert.match((await noToken.response.json()).notify, /NOTIFY_TOKEN/);

  const off = await run("https://vibresia.com/api/health", {
    env: makeEnv({ DISCORD_NOTIFICATIONS_ENABLED: "false" }),
  });
  assert.match((await off.response.json()).discord, /disabled/);

  const missing = await run("https://vibresia.com/api/health", {
    env: makeEnv({ DISCORD_WEBHOOK_URL: "" }),
  });
  assert.match((await missing.response.json()).discord, /wrangler secret put/);
});

test("the payload is truncated to what Discord accepts", () => {
  const embed = buildDownloadEmbed({
    source: "x".repeat(500),
    referer: "https://example.com/" + "y".repeat(5000),
    country: "GB",
    city: "Alton",
    agent: "z".repeat(5000),
    firstSeen: false,
  });
  for (const field of embed.embeds[0].fields) {
    assert.ok(field.value.length <= 1024, `${field.name} is ${field.value.length} chars`);
  }
});