#!/usr/bin/env node
// Fills in the payload hashes for the shares that were made before the column
// existed.
//
//   node scripts/backfill-share-payload-hashes.mjs [--local]
//
// The Worker can find a share by its key — the hash the app sends of the
// vibescape's contents — or by the hash of the payload it holds. Rows made
// before either of those columns existed have neither, so the Worker has to
// fall back to looking for the payload itself, which means reading every row
// in the table. This fills them in, so that fallback is only ever needed for
// rows made in the seconds between the migration and this script.
//
// Run it once, after the migration, before the Worker that uses the new
// columns is deployed.

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const local = process.argv.includes("--local");
const flags = local ? ["--local"] : [];
const database = "vibresia-shares";

function wrangler(args, options = {}) {
  return execFileSync("npx", ["wrangler", "d1", "execute", database, ...flags, ...args], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    ...options,
  });
}

/** The rows out of wrangler's JSON, which wraps them one level deeper than
 *  you would expect: an array of `{results: [...]}` objects. */
function rowsFrom(text) {
  const parsed = JSON.parse(text);
  const out = [];
  for (const entry of Array.isArray(parsed) ? parsed : [parsed]) {
    if (entry && Array.isArray(entry.results)) out.push(...entry.results);
    else if (entry) out.push(entry);
  }
  return out;
}

console.log("==> Reading the shares that have no hash yet");
const rows = rowsFrom(
  wrangler(["--command", "SELECT id, payload FROM shares WHERE payload_hash IS NULL", "--json"])
);

if (rows.length === 0) {
  console.log("==> Nothing to do — every share has a hash");
  process.exit(0);
}

console.log(`==> ${rows.length} share(s) to hash`);
const statements = rows.map((row) => {
  const hash = createHash("sha256").update(row.payload, "utf8").digest("hex");
  const id = String(row.id).replace(/'/g, "''");
  return `UPDATE shares SET payload_hash = '${hash}' WHERE id = '${id}';`;
});

console.log("==> Writing the hashes");
// Wrangler wants a file rather than standard input.
const file = join(tmpdir(), `vibresia-backfill-${process.pid}.sql`);
writeFileSync(file, statements.join("\n"));
try {
  wrangler(["--file", file]);
} finally {
  rmSync(file, { force: true });
}
console.log("==> Done");
