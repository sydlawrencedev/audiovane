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
      const statement = {
        bind(...args) {
          return {
            async run() {
              if (sql.includes("INSERT INTO shares")) {
                const [id, payload, name, author, image, key, payloadHash] = args;
                if (rows.has(id)) throw new Error("UNIQUE constraint failed: shares.id");
                if (key && byKey.has(key)) {
                  throw new Error("UNIQUE constraint failed: shares.key");
                }
                rows.set(id, {
                  id, payload, name, author, image,
                  key: key || null,
                  payload_hash: payloadHash || null,
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
                return { ...row, image: row.image ? Array.from(row.image) : null };
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
        fetch: async () =>
          new Response(
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
</head><body>hi</body></html>`,
            { status: 200 }
          ),
      },
      SHARE_TOKEN,
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
    ...shareRequest({ payload: PAYLOAD, name: "My World", author: "Stephen" }),
  });
  const { id } = await created.json();
  const html = await (await run(`https://vibresia.com/s/${id}`, { env })).text();

  assert.ok(html.includes("<title>My World — Vibresia</title>"));
  assert.ok(html.includes('<meta property="og:title" content="My World — Vibresia">'));
  assert.ok(html.includes(`<meta property="og:image" content="https://vibresia.com/og/${id}.jpg">`));
  assert.ok(html.includes("by Stephen"));
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
