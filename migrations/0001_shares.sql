-- Shared custom vibescapes.
--
-- One row per share. The payload is the base64url of the deflated JSON the
-- app already puts in a share link; it is kept verbatim so the page the
-- Worker serves is byte-for-byte the page the long URL would have produced.
--
-- The image is the 1200x630 JPEG the app renders, stored here so the
-- og:image can point at something specific to this vibescape. Without it the
-- preview is the generic Vibresia picture, which is what every custom share
-- used to look like.
--
-- The id is short on purpose: it is the whole URL a person shares. Six
-- characters of base32 is about 1 billion ids, and a recipient typing one
-- out has a chance of getting it right.
CREATE TABLE IF NOT EXISTS shares (
    id         TEXT PRIMARY KEY,
    payload    TEXT NOT NULL,
    name       TEXT NOT NULL,
    author     TEXT NOT NULL,
    image      BLOB,
    created_at INTEGER NOT NULL
);

-- Nothing reads by time, but the cleanup sweep does, and an index on it
-- keeps that sweep from scanning the whole table.
CREATE INDEX IF NOT EXISTS shares_created_at ON shares (created_at);
