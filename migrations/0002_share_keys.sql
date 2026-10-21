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
