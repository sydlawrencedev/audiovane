-- The key a share is looked up by.
--
-- A share used to be made fresh every time: a new row, a new id, a new URL,
-- for the same vibescape. So sharing the same vibescape twice gave you two
-- links, and re-sharing one somebody sent you gave you a third.
--
-- The key is a hash of the vibescape's content — its name, author, url and
-- shader — so the same vibescape always resolves to the same row. The app
-- sends it; a share that arrives without one still works, because the
-- Worker falls back to looking for an identical payload.
--
-- Nullable, and the index is partial: rows made before this column existed
-- have no key, and several of them must not collide on NULL.
ALTER TABLE shares ADD COLUMN key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS shares_key ON shares (key) WHERE key IS NOT NULL;

-- The hash of the payload, so a share can be found by what it holds
-- without reading every row in the table.
--
-- A payload is too long to index — SQLite caps an index key at about a page
-- — and looking for one by value means a scan of the whole table, which D1
-- charges for row by row. The hash is the same length as the key and
-- indexes like it.
--
-- Nullable, because the rows that existed before this column did have no
-- hash; the Worker falls back to the payload itself for those, and there
-- are only a handful of them.
--
-- Backfill the rows that are already there with:
--   scripts/backfill-share-payload-hashes.sh
ALTER TABLE shares ADD COLUMN payload_hash TEXT;

CREATE INDEX IF NOT EXISTS shares_payload_hash ON shares (payload_hash);
