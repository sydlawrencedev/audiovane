// Tests for the shared-vibescape part of the Worker.
//
// The D1 binding is faked with a tiny in-memory table, because the point of
// these tests is the rules — who may create a share, what may be in it, and
// what the served page says — not SQLite.

import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";

import worker, { buildSharePage, toBytes, resetRateLimiter } from "./index.js";

const SHARE_TOKEN = "share-token-for-tests";
const PAYLOAD = "TZDNbsMgEIRfZcUJYoqIU6dtqjxCT63USy8oIcESBosfK1GUd-8CVZWLBd_M7oy5EZWT8YHsyGfSs9GOcOLUpBF8XOF";

/** A D1 stand-in: just enough SQL for the queries the Worker makes. */
function makeShares() {
  const rows = new Map();
  const byKey = new Map();
  const byPayloadHash = new Map();
  return {
    rows,
    byKey,
    byPayloadHash,
    prepare(sql) {
      // `.all()` is called without bindings — the gallery's query has no
      // parameters — so it lives on the statement as well as on the bound
      // one.
      const all = async () => {
        if (sql.includes("WHERE is_public = 1")) {
          return {
            results: [...rows.values()].filter((row) => (row.is_public ? 1 : 0) === 1),
          };
        }
        return { results: [...rows.values()] };
      };
      const statement = {
        all,
        bind(...args) {
          return {
            all,
            async run() {
              if (sql.includes("INSERT INTO shares")) {
                const [id, payload, name, author, image, key, payloadHash, isPublic] = args;
                if (rows.has(id)) throw new Error("UNIQUE constraint failed: shares.id");
                if (key && byKey.has(key)) {
                  throw new Error("UNIQUE constraint failed: shares.key");
                }
                rows.set(id, {
                  id, payload, name, author, image,
                  key: key || null,
                  payload_hash: payloadHash || null,
                  is_public: isPublic ? 1 : 0,
                  created_at: 1_700_000_000_000,
                });
                if (key) byKey.set(key, id);
                if (payloadHash) byPayloadHash.set(payloadHash, id);
                return { success: true };
              }
              if (sql.includes("UPDATE shares SET image")) {
                const [image, id] = args;
                const row = rows.get(id);
                if (row) row.image = image;
                return { success: true };
              }
              if (sql.includes("UPDATE shares SET is_public")) {
                const [isPublic, id] = args;
                const row = rows.get(id);
                if (row) row.is_public = isPublic;
                return { success: true };
              }
              if (sql.includes("DELETE FROM shares")) {
                const id = args[0];
                const existed = rows.delete(id);
                for (const [key, value] of byKey) if (value === id) byKey.delete(key);
                for (const [key, value] of byPayloadHash) if (value === id) byPayloadHash.delete(key);
                return { success: true, meta: { changes: existed ? 1 : 0 } };
              }
              return { success: true };
            },
            async first() {
              if (sql.includes("WHERE key = ?")) {
                const id = byKey.get(args[0]);
                if (!id) return null;
                const row = rows.get(id);
                return { ...row, image: row.image ? Array.from(row.image) : null };
              }
              if (sql.includes("WHERE payload_hash = ?")) {
                const id = byPayloadHash.get(args[0]);
                if (!id) return null;
                const row = rows.get(id);
                return { ...row, image: row.image ? Array.from(row.image) : null };
              }
              if (sql.includes("WHERE payload = ?")) {
                for (const row of rows.values()) {
                  if (row.payload === args[0]) {
                    return { ...row, image: row.image ? Array.from(row.image) : null };
                  }
                }
                return null;
              }
              if (sql.includes("FROM shares WHERE id = ?")) {
                const row = rows.get(args[0]);
                if (!row) return null;
                // D1 hands BLOBs back as a plain array of bytes, which is what
                // the code has to cope with.
                // The picture flag comes out of the SELECT, so the fake
                // works it out rather than reading it off the row.
                return {
                  ...row,
                  image: row.image ? Array.from(row.image) : null,
                  has_image: row.image ? 1 : 0,
                };
              }
              return null;
            },
          };
        },
      };
      return statement;
    },
  };
}

function makeEnv(overrides = {}) {
  const shares = makeShares();
  return {
    env: {
      ASSETS: {
        fetch: async (request) => {
          const path = new URL(request.url).pathname;
          if (path === "/share/manifest.json") {
            return new Response(JSON.stringify({
              generated: "test",
              base: "https://vibresia.com",
              built_ins: [
                { slug: "ribbons", title: "Ribbons", date: "2026-10-19" },
                { slug: "band", title: "The Band", date: "2026-10-18" },
              ],
            }), { status: 200 });
          }
          return new Response(
            `<!doctype html><html><head><title>A vibescape was shared with you — Vibresia</title>
<meta name="description" content="Someone shared a Vibresia vibescape with you.">
<link rel="canonical" href="https://vibresia.com/share">
<meta property="og:url" content="https://vibresia.com/share">
<meta property="og:title" content="A vibescape was shared with you — Vibresia">
<meta property="og:description" content="Someone shared a Vibresia vibescape with you.">
<meta property="og:image" content="https://vibresia.com/media/share.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:title" content="A vibescape was shared with you — Vibresia">
<meta name="twitter:description" content="Someone shared a Vibresia vibescape with you.">
<meta name="twitter:image" content="https://vibresia.com/media/share.jpg">
<!-- gallery:builtin-cards -->
<!-- gallery:cards -->
</head><body>hi</body></html>`,
            { status: 200 }
          );
        },
      },
      SHARE_TOKEN,
      ADMIN_TOKEN: "admin-token-for-tests",
      SHARES: shares,
      ...overrides,
    },
    shares,
  };
}

async function run(url, { env, headers = {}, method = "GET", body } = {}) {
  const request = new Request(url, { method, headers, body });
  const ctx = { waitUntil: () => {} };
  return worker.fetch(request, env, ctx);
}

function shareRequest(body, token = SHARE_TOKEN) {
  return {
    method: "POST",
    headers: { "x-av-token": token, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

beforeEach(() => {
  resetRateLimiter();
});

// --- creating a share ------------------------------------------------------

test("a share needs the token", async () => {
  const { env } = makeEnv();
  const response = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "A" }, "wrong-token"),
  });
  assert.equal(response.status, 401);
});

test("a share comes back with a short URL on this domain", async () => {
  const { env } = makeEnv();
  const response = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "My World", author: "Stephen" }),
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.ok, true);
  assert.match(body.url, /^https:\/\/vibresia\.com\/s\/[a-z2-9]{6}$/);
  assert.equal(body.imageUrl, null);
});

test("a payload that is not a payload is refused", async () => {
  const { env } = makeEnv();
  for (const payload of ["", "not base64!", "x".repeat(9000), "../../etc/passwd"]) {
    // The rate limiter runs before the validation, so a burst of rubbish
    // still counts against the budget — that is the point of it. Reset
    // between cases so this is testing the validation and not the limiter.
    resetRateLimiter();
    const response = await run("https://vibresia.com/api/share", {
      env,
      ...shareRequest({ payload, name: "A" }),
    });
    assert.equal(response.status, 400, `should refuse ${JSON.stringify(payload.slice(0, 20))}`);
  }
});

test("a name or an author that is too long is refused", async () => {
  const { env } = makeEnv();
  const long = "x".repeat(200);
  const response = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: long }),
  });
  assert.equal(response.status, 400);
});

test("an image over the cap is refused rather than stored", async () => {
  const { env } = makeEnv();
  const big = Buffer.alloc(500 * 1024).toString("base64");
  const response = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "A", image: big }),
  });
  assert.equal(response.status, 400);
});

test("a share with a picture gets an image URL, and the picture comes back", async () => {
  const { env } = makeEnv();
  const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
  const response = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "A", image: Buffer.from(jpeg).toString("base64") }),
  });
  const body = await response.json();
  assert.match(body.imageUrl, /^https:\/\/vibresia\.com\/og\/[a-z2-9]{6}\.jpg$/);

  const image = await run(body.imageUrl, { env });
  assert.equal(image.status, 200);
  assert.equal(image.headers.get("content-type"), "image/jpeg");
  assert.equal(image.headers.get("cache-control"), "public, max-age=31536000, immutable");
  const bytes = new Uint8Array(await image.arrayBuffer());
  assert.deepEqual([...bytes], [...jpeg]);
});

// --- the same vibescape, the same link ---------------------------------------

test("the same vibescape shared twice gets the same link", async () => {
  const { env } = makeEnv();
  const first = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "My World", author: "Stephen", key: "abc123" }),
  });
  const firstBody = await first.json();
  assert.equal(firstBody.existing, false);

  // One per second, so a person sharing twice in a row is fine but two
  // requests in the same test are not.
  resetRateLimiter();
  const second = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "My World", author: "Stephen", key: "abc123" }),
  });
  const secondBody = await second.json();
  assert.equal(secondBody.existing, true);
  assert.equal(secondBody.id, firstBody.id);
  assert.equal(secondBody.url, firstBody.url);
});

test("the same vibescape without a key still gets the same link", async () => {
  const { env } = makeEnv();
  const first = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "My World" }),
  });
  const firstBody = await first.json();
  // One per second, so a person sharing twice in a row is fine but two
  // requests in the same test are not.
  resetRateLimiter();
  const second = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "My World" }),
  });
  const secondBody = await second.json();
  assert.equal(secondBody.id, firstBody.id);
  assert.equal(secondBody.url, firstBody.url);
});

test("a different vibescape gets a different link", async () => {
  const { env } = makeEnv();
  const first = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "One", key: "key-one" }),
  });
  // One per second, so a person sharing twice in a row is fine but two
  // requests in the same test are not.
  resetRateLimiter();
  const second = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: "Zm91ci1vdGhlci1wYXlsb2Fk", name: "Two", key: "key-two" }),
  });
  const firstBody = await first.json();
  const secondBody = await second.json();
  assert.notEqual(secondBody.id, firstBody.id);
});

test("a share made without a picture gets one when it is shared again with one", async () => {
  const { env } = makeEnv();
  const first = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "A", key: "abc123" }),
  });
  const firstBody = await first.json();
  assert.equal(firstBody.imageUrl, null);

  const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
  // One per second, so a person sharing twice in a row is fine but two
  // requests in the same test are not.
  resetRateLimiter();
  const second = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({
      payload: PAYLOAD, name: "A", key: "abc123",
      image: Buffer.from(jpeg).toString("base64"),
    }),
  });
  const secondBody = await second.json();
  assert.equal(secondBody.id, firstBody.id);
  assert.match(secondBody.imageUrl, /\/og\/[a-z2-9]{6}\.jpg$/);

  const image = await run(secondBody.imageUrl, { env });
  assert.equal(image.status, 200);
});

test("a key that isn't a key is refused", async () => {
  const { env } = makeEnv();
  for (const key of ["", "x".repeat(200), "not a key!", "../../etc/passwd"]) {
    resetRateLimiter();
    const response = await run("https://vibresia.com/api/share", {
      env,
      ...shareRequest({ payload: PAYLOAD, name: "A", key }),
    });
    // An empty key is simply no key; anything else has to be refused.
    if (key === "") {
      assert.equal(response.status, 200);
    } else {
      assert.equal(response.status, 400, `should refuse ${JSON.stringify(key)}`);
    }
  }
});

test("creating shares in a loop is rate limited", async () => {
  const { env } = makeEnv();
  let created = 0;
  for (let i = 0; i < 5; i += 1) {
    const response = await run("https://vibresia.com/api/share", {
      env,
      ...shareRequest({ payload: PAYLOAD, name: "A" }),
    });
    if (response.status === 200) created += 1;
    else assert.equal(response.status, 429);
  }
  assert.ok(created >= 1 && created <= 2, `expected a few to get through, got ${created}`);
});

// --- serving a share -------------------------------------------------------

test("the share page has the payload inlined and the URL stays short", async () => {
  const { env } = makeEnv();
  const created = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "My World", author: "Stephen" }),
  });
  const { id } = await created.json();

  const response = await run(`https://vibresia.com/s/${id}`, { env });
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.ok(html.includes(`window.__VIBRESIA_SHARE__ = {"d":"${PAYLOAD}","id":"${id}"}`), "payload not inlined");
  // The id goes with it, so the page can put it in the deep link and the app
  // can hand the same link back when the vibescape is shared on.
  assert.ok(html.includes(`"id":"${id}"`), "the share's id was not inlined");
  assert.ok(html.includes(`<meta property="og:url" content="https://vibresia.com/s/${id}">`));
});

test("the metadata names the vibescape and points at its own picture", async () => {
  const { env } = makeEnv();
  const created = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "My World", author: "Stephen",
                      image: Buffer.from([0xff, 0xd8, 0xff]).toString("base64") }),
  });
  const { id } = await created.json();
  const html = await (await run(`https://vibresia.com/s/${id}`, { env })).text();

  assert.ok(html.includes("<title>My World — Vibresia</title>"));
  assert.ok(html.includes('<meta property="og:title" content="My World — Vibresia">'));
  assert.ok(html.includes(`<meta property="og:image" content="https://vibresia.com/og/${id}.jpg">`));
  assert.ok(html.includes("by Stephen"));
});

test("a share with no picture of its own gets the general one, not a broken link", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  const created = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "No Picture", author: "Nobody" }),
  });
  const { id } = await created.json();
  const html = await (await run(`https://vibresia.com/s/${id}`, { env })).text();
  // An agent's share has no picture, because the server cannot draw one.
  // Pointing the preview at a picture that is not there would be worse than
  // the general one.
  assert.ok(html.includes('<meta property="og:image" content="https://vibresia.com/media/share.jpg">'));
  assert.ok(!html.includes(`content="https://vibresia.com/og/${id}.jpg"`));
});

test("a name with markup in it is escaped, not pasted in", async () => {
  const { env } = makeEnv();
  const created = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: '"><script>alert(1)</script>', author: "x" }),
  });
  const { id } = await created.json();
  const html = await (await run(`https://vibresia.com/s/${id}`, { env })).text();

  assert.ok(!html.includes("<script>alert(1)</script>"), "markup was not escaped");
  assert.ok(html.includes("&lt;script&gt;"));
});

test("a name with a dollar in it does not paste the page into itself", async () => {
  // `String.replace` treats `$&` and `$'` in a replacement as patterns, and
  // the replacement here is a name somebody typed. Without a function
  // replacement, "evil$'x" pasted the page's own title into the middle of
  // the new one.
  const { env } = makeEnv();
  for (const name of ["evil$&x", "evil$`x", "evil$'x", "$$", "a$1b"]) {
    resetRateLimiter();
    const created = await run("https://vibresia.com/api/share", {
      env,
      ...shareRequest({ payload: PAYLOAD, name, author: "x" }),
    });
    const { id } = await created.json();
    const html = await (await run(`https://vibresia.com/s/${id}`, { env })).text();

    const title = html.match(/<title>([^<]*)<\/title>/);
    assert.ok(title, `no title for ${JSON.stringify(name)}`);
    assert.ok(!title[1].includes("<"), `the title was mangled: ${title[1]}`);
    assert.equal((html.match(/<title>/g) || []).length, 1, "the title was duplicated");
  }
});

test("a share that does not exist is a 404, and so is a nonsense id", async () => {
  const { env } = makeEnv();
  assert.equal((await run("https://vibresia.com/s/aaaaaa", { env })).status, 404);
  assert.equal((await run("https://vibresia.com/s/NOT-A-VALID-ID", { env })).status, 404);
  assert.equal((await run("https://vibresia.com/og/aaaaaa.jpg", { env })).status, 404);
});

test("a share with no picture has no picture, rather than a broken one", async () => {
  const { env } = makeEnv();
  const created = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "A" }),
  });
  const { id } = await created.json();
  assert.equal((await run(`https://vibresia.com/og/${id}.jpg`, { env })).status, 404);
});

// --- the gallery ------------------------------------------------------------

/** The shares people made, not the built-ins — which are always in the list. */
function sharedIn(gallery) {
  return gallery.vibescapes.filter((v) => !v.builtin);
}

test("the gallery lists the shares that were ticked into it", async () => {
  const { env } = makeEnv();
  // A public share and a private one.
  resetRateLimiter();
  await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "In The Gallery", author: "Stephen", key: "gallery1", public: true }),
  });
  resetRateLimiter();
  await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: "Zm91ci1vdGhlci1wYXlsb2Fk", name: "Kept Out", author: "Nobody", key: "hidden1", public: false }),
  });

  const api = await run("https://vibresia.com/api/gallery", { env });
  const body = await api.json();
  assert.equal(body.ok, true);
  const shared = sharedIn(body);
  assert.equal(shared.length, 1);
  assert.equal(shared[0].name, "In The Gallery");
  assert.equal(shared[0].author, "Stephen");
  // The built-ins are in the gallery too.
  assert.equal(body.vibescapes.filter((v) => v.builtin).length, 2);
});

test("a share is only in the gallery if it was ticked in", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Quiet", author: "Nobody", key: "quiet1" }),
  });
  const body = await (await run("https://vibresia.com/api/gallery", { env })).json();
  assert.equal(sharedIn(body).length, 0);
});

test("sharing it again with the tickbox on puts it in the gallery", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Later", author: "Stephen", key: "later1" }),
  });
  let body = await (await run("https://vibresia.com/api/gallery", { env })).json();
  assert.equal(sharedIn(body).length, 0);

  resetRateLimiter();
  await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Later", author: "Stephen", key: "later1", public: true }),
  });
  body = await (await run("https://vibresia.com/api/gallery", { env })).json();
  assert.equal(sharedIn(body).length, 1);
  assert.equal(sharedIn(body)[0].name, "Later");
});

test("the gallery page is a page, with the shares on it", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "On The Page", author: "Stephen", key: "page1", public: true }),
  });
  const response = await run("https://vibresia.com/vibescapes", { env });
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.ok(html.includes("On The Page"), "the share was not on the page");
  assert.ok(html.includes("/s/"), "the share was not linked");
});

// --- the admin --------------------------------------------------------------

test("the admin needs the admin token", async () => {
  const { env } = makeEnv();
  for (const headers of [{}, { "x-av-admin-token": "wrong" }]) {
    const response = await run("https://vibresia.com/api/admin/shares", { env, headers });
    assert.equal(response.status, 401);
  }
  const ok = await run("https://vibresia.com/api/admin/shares", {
    env, headers: { "x-av-admin-token": "admin-token-for-tests" },
  });
  assert.equal(ok.status, 200);
});

test("the admin sees the shares that are hidden as well as the ones that are not", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Listed", author: "Stephen", key: "listed1", public: true }),
  });
  resetRateLimiter();
  await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: "aGlkZGVu", name: "Hidden", author: "Nobody", key: "hidden2" }),
  });

  const body = await (await run("https://vibresia.com/api/admin/shares", {
    env, headers: { "x-av-admin-token": "admin-token-for-tests" },
  })).json();
  assert.equal(body.ok, true);
  const names = body.shares.map((s) => s.name).sort();
  assert.deepEqual(names, ["Hidden", "Listed"]);
  assert.equal(body.shares.find((s) => s.name === "Hidden").inGallery, false);
  assert.equal(body.shares.find((s) => s.name === "Listed").inGallery, true);
});

test("hiding a share takes it out of the gallery and leaves the link working", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  const created = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Hide Me", author: "Stephen", key: "hide1", public: true }),
  });
  const { id } = await created.json();

  const hidden = await run(`https://vibresia.com/api/admin/shares/${id}`, {
    env,
    method: "POST",
    headers: { "x-av-admin-token": "admin-token-for-tests", "Content-Type": "application/json" },
    body: JSON.stringify({ action: "hide" }),
  });
  assert.equal(hidden.status, 200);

  const gallery = await (await run("https://vibresia.com/api/gallery", { env })).json();
  assert.equal(sharedIn(gallery).length, 0);

  // The link still works: hiding is not deleting.
  const page = await run(`https://vibresia.com/s/${id}`, { env });
  assert.equal(page.status, 200);
});

test("showing a share puts it back in the gallery", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  const created = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Show Me", author: "Stephen", key: "show1" }),
  });
  const { id } = await created.json();

  await run(`https://vibresia.com/api/admin/shares/${id}`, {
    env,
    method: "POST",
    headers: { "x-av-admin-token": "admin-token-for-tests", "Content-Type": "application/json" },
    body: JSON.stringify({ action: "show" }),
  });
  const gallery = await (await run("https://vibresia.com/api/gallery", { env })).json();
  assert.equal(sharedIn(gallery).length, 1);
});

test("deleting a share takes the link with it", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  const created = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Delete Me", author: "Stephen", key: "del1", public: true }),
  });
  const { id } = await created.json();

  const deleted = await run(`https://vibresia.com/api/admin/shares/${id}`, {
    env,
    method: "POST",
    headers: { "x-av-admin-token": "admin-token-for-tests", "Content-Type": "application/json" },
    body: JSON.stringify({ action: "delete" }),
  });
  assert.equal(deleted.status, 200);
  assert.equal((await run(`https://vibresia.com/s/${id}`, { env })).status, 404);
  const gallery = await (await run("https://vibresia.com/api/gallery", { env })).json();
  assert.equal(sharedIn(gallery).length, 0);
});

test("the admin cannot delete a share that isn't there", async () => {
  const { env } = makeEnv();
  const response = await run("https://vibresia.com/api/admin/shares/aaaaaa", {
    env,
    method: "POST",
    headers: { "x-av-admin-token": "admin-token-for-tests", "Content-Type": "application/json" },
    body: JSON.stringify({ action: "delete" }),
  });
  assert.equal(response.status, 404);
});

// --- the gallery ------------------------------------------------------------

test("the gallery is one list, newest first", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Shared", author: "Stephen", key: "shared1", public: true }),
  });
  const body = await (await run("https://vibresia.com/api/gallery", { env })).json();

  // The built-ins are in it, with the shares people made.
  assert.ok(body.vibescapes.some((v) => v.builtin && v.name === "Ribbons"));
  assert.ok(body.vibescapes.some((v) => !v.builtin && v.name === "Shared"));

  // Newest first: a share made now is above a built-in from the 18th.
  const dates = body.vibescapes.map((v) => v.sharedAt);
  const sorted = [...dates].sort((a, b) => b - a);
  assert.deepEqual(dates, sorted);

  // The built-ins carry the day they appeared, and the clean still rather
  // than the framed share graphic.
  const ribbons = body.vibescapes.find((v) => v.id === "ribbons");
  assert.equal(ribbons.imageUrl, "https://vibresia.com/media/modes/ribbons.jpg");
  assert.equal(ribbons.url, "https://vibresia.com/share/ribbons");
  assert.ok(ribbons.sharedAt > 0);
});

// --- the pure parts --------------------------------------------------------

test("a share with no name still gets a usable title and the payload", () => {
  const html = "<html><head><title>Same</title></head><body></body></html>";
  const out = buildSharePage(html, {
    id: "aaaaaa",
    payload: PAYLOAD,
    name: "",
    author: "",
    url: "https://vibresia.com/s/aaaaaa",
  });
  assert.ok(out.includes("<title>A vibescape was shared with you — Vibresia</title>"));
  assert.ok(out.includes(`window.__VIBRESIA_SHARE__ = {"d":"${PAYLOAD}","id":"aaaaaa"}`));
});

test("a payload cannot close the script tag it is in", () => {
  const html = "<html><head></head><body></body></html>";
  const out = buildSharePage(html, {
    id: "aaaaaa",
    payload: "abc</script><script>alert(1)</script>",
    name: "",
    author: "",
    url: "https://vibresia.com/s/aaaaaa",
  });
  assert.ok(!out.includes("</script><script>alert(1)"), "the script tag was closed early");
  assert.ok(out.includes("\\u003c/script>"));
});

test("bytes come out of D1 in whichever shape it hands them over", () => {
  assert.deepEqual([...toBytes(new Uint8Array([1, 2, 3]))], [1, 2, 3]);
  assert.deepEqual([...toBytes(new Uint8Array([1, 2, 3]).buffer)], [1, 2, 3]);
  assert.deepEqual([...toBytes([1, 2, 3])], [1, 2, 3]);
  assert.equal(toBytes(null), null);
  assert.equal(toBytes(undefined), null);
});

// --- the gallery tickbox, and replacing a share -----------------------------

test("the gallery tickbox reaches the site", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  const created = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Ticked", author: "Stephen", key: "ticked1", public: true }),
  });
  const { id } = await created.json();

  // Unticking it takes the share out of the gallery, which it never used to
  // do: the tickbox was only read when a share was made.
  const patched = await run(`https://vibresia.com/api/share/${id}`, {
    env,
    method: "PATCH",
    headers: { "x-av-token": SHARE_TOKEN, "Content-Type": "application/json" },
    body: JSON.stringify({ public: false }),
  });
  assert.equal(patched.status, 200);

  const gallery = await (await run("https://vibresia.com/api/gallery", { env })).json();
  assert.equal(sharedIn(gallery).length, 0, "the share is still in the gallery");

  // And the share says so, so the app's tickbox can show what is true.
  const details = await (await run(`https://vibresia.com/api/share/${id}`, { env })).json();
  assert.equal(details.ok, true);
  assert.equal(details.public, false);
  assert.equal(details.name, "Ticked");
});

test("the gallery tickbox needs the token", async () => {
  const { env } = makeEnv();
  const response = await run("https://vibresia.com/api/share/aaaaaa", {
    env,
    method: "PATCH",
    headers: { "x-av-token": "wrong", "Content-Type": "application/json" },
    body: JSON.stringify({ public: false }),
  });
  assert.equal(response.status, 401);
});

test("a share that does not exist is a 404", async () => {
  const { env } = makeEnv();
  const response = await run("https://vibresia.com/api/share/aaaaaa", { env });
  assert.equal(response.status, 404);
});

test("changing your name replaces the share rather than leaving it behind", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  const first = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Before", author: "Stephen", key: "before1", public: true }),
  });
  const { id: oldId } = await first.json();

  // The name is part of the payload, so a new name is a different vibescape
  // and gets its own link — and says which share it replaces.
  resetRateLimiter();
  const second = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({
      payload: "QU5PVEhFUi1wYXlsb2Fk", name: "After", author: "Stephen",
      key: "after1", public: true, replaces: oldId,
    }),
  });
  const { id: newId } = await second.json();
  assert.notEqual(newId, oldId);

  // The old share is gone, so the gallery does not fill up with every
  // version of the same vibescape.
  const gallery = await (await run("https://vibresia.com/api/gallery", { env })).json();
  assert.equal(sharedIn(gallery).length, 1);
  assert.equal(sharedIn(gallery)[0].name, "After");
  assert.equal((await run(`https://vibresia.com/api/share/${oldId}`, { env })).status, 404);
});

test("a share that replaces itself is not deleted", async () => {
  const { env } = makeEnv();
  resetRateLimiter();
  const created = await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({ payload: PAYLOAD, name: "Same", author: "Stephen", key: "same1", public: true }),
  });
  const { id } = await created.json();

  // Sharing the same vibescape again finds the share that is already there
  // rather than making a second one, so the one that is there must survive.
  resetRateLimiter();
  await run("https://vibresia.com/api/share", {
    env,
    ...shareRequest({
      payload: PAYLOAD, name: "Same", author: "Stephen",
      key: "same1", public: true, replaces: id,
    }),
  });
  assert.equal((await run(`https://vibresia.com/api/share/${id}`, { env })).status, 200);
});
