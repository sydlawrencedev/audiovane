// Tests for the Worker: node --test worker/
//
// The Discord POST is captured by replacing global fetch, so nothing here
// touches the network or needs a webhook — the same reason delphina mocks
// `https` in its notification tests. Keeping the payload builder pure is what
// makes that possible.

import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";

import worker, { buildDownloadEmbed, isDiscordEnabled, resetRateLimiter } from "./index.js";

const RELEASE_ZIP =
  "https://github.com/sydlawrencedev/audiovane/releases/latest/download/AudioVane.zip";

function makeEnv(overrides = {}) {
  return {
    ASSETS: { fetch: async () => new Response("asset", { status: 200 }) },
    DISCORD_WEBHOOK_URL: "https://discord.com/api/webhooks/1/token",
    DISCORD_NOTIFICATIONS_ENABLED: "true",
    DISCORD_BOT_USERNAME: "AudioVane",
    ...overrides,
  };
}

/** Runs the worker with fetch stubbed, returning the response and every POST. */
async function run(url, { env = makeEnv(), headers = {}, cf = {} } = {}) {
  const posts = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (target, init) => {
    posts.push({ url: String(target), body: JSON.parse(init.body) });
    // 204 is what a Discord webhook actually answers, and it carries no body.
    return new Response(null, { status: 204 });
  };
  const request = new Request(url, { headers });
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
  const { response, posts } = await run("https://audiovane.minithlabs.com/download?src=hero&seen=0", {
    headers: { "user-agent": BROWSER_UA, referer: "https://audiovane.minithlabs.com/" },
  });
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), RELEASE_ZIP);
  assert.equal(posts.length, 1);
});

test("the notification says who, where and whether it is a repeat", async () => {
  const { posts } = await run("https://audiovane.minithlabs.com/download?src=hero&seen=1", {
    headers: { "user-agent": BROWSER_UA, referer: "https://audiovane.minithlabs.com/?x=1" },
    cf: { country: "GB", city: "Alton" },
  });
  const embed = posts[0].body.embeds[0];
  const fields = Object.fromEntries(embed.fields.map((f) => [f.name, f.value]));
  assert.match(embed.title, /downloaded AudioVane/);
  assert.equal(posts[0].body.username, "AudioVane");
  assert.equal(fields.Source, "hero");
  assert.equal(fields.Where, "Alton, GB");
  assert.match(fields["Seen before"], /has downloaded before/);
  assert.equal(embed.url, RELEASE_ZIP);
});

test("a first download says so, and a missing src is not invented", async () => {
  const { posts } = await run("https://audiovane.minithlabs.com/download", {
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
  const first = await run("https://audiovane.minithlabs.com/download?src=hero&seen=0", {
    headers: { "user-agent": BROWSER_UA },
  });
  const second = await run("https://audiovane.minithlabs.com/download?src=hero&seen=0", {
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
    const { response, posts } = await run("https://audiovane.minithlabs.com/download", {
      headers: { "user-agent": agent },
    });
    assert.equal(response.status, 302, `${agent} still gets the file`);
    assert.equal(posts.length, 0, `${agent} should not post`);
  }
});

test("no webhook configured means a silent download, not an error", async () => {
  const { response, posts } = await run("https://audiovane.minithlabs.com/download", {
    env: makeEnv({ DISCORD_WEBHOOK_URL: "", DISCORD_NOTIFICATIONS_ENABLED: "true" }),
    headers: { "user-agent": BROWSER_UA },
  });
  assert.equal(response.status, 302);
  assert.equal(posts.length, 0);
});

test("the switch really is off when it says it is", async () => {
  const env = makeEnv({ DISCORD_NOTIFICATIONS_ENABLED: "false" });
  assert.equal(isDiscordEnabled(env), false);
  const { response, posts } = await run("https://audiovane.minithlabs.com/download", {
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
  const request = new Request("https://audiovane.minithlabs.com/download", {
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
  const http = await run("http://audiovane.minithlabs.com/");
  assert.equal(http.response.status, 301);
  assert.equal(http.response.headers.get("location"), "https://audiovane.minithlabs.com/");

  const www = await run("https://www.audiovane.minithlabs.com/download?src=hero");
  assert.equal(www.response.status, 301);
  assert.equal(www.response.headers.get("location"), "https://audiovane.minithlabs.com/download?src=hero");
});

test("local dev is left alone", async () => {
  // `wrangler dev` rewrites Host to the production hostname over plain http.
  // Redirecting there would loop /download back onto itself forever, so the
  // miniflare proxy's header is what marks a request as local.
  const { response, posts } = await run("http://audiovane.minithlabs.com/download?src=hero&seen=0", {
    headers: { "user-agent": BROWSER_UA, "mf-original-hostname": "127.0.0.1:8787" },
  });
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), RELEASE_ZIP);
  assert.equal(posts.length, 1);

  const onLocalhost = await run("http://localhost:8787/", { headers: { host: "localhost:8787" } });
  assert.equal(onLocalhost.response.status, 200);
});

test("everything else falls through to the static assets", async () => {
  const { response, posts } = await run("https://audiovane.minithlabs.com/index.html");
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "asset");
  assert.equal(posts.length, 0);
});

test("health reports which state the webhook is in", async () => {
  const ok = await run("https://audiovane.minithlabs.com/api/health");
  assert.deepEqual(await ok.response.json(), { ok: true, discord: "configured" });

  const off = await run("https://audiovane.minithlabs.com/api/health", {
    env: makeEnv({ DISCORD_NOTIFICATIONS_ENABLED: "false" }),
  });
  assert.match((await off.response.json()).discord, /disabled/);

  const missing = await run("https://audiovane.minithlabs.com/api/health", {
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