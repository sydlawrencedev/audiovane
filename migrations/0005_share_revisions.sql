-- The revision of a share, and who may change it.
--
-- A share used to be a fixed thing: made once, and changed by making a new
-- one and deleting the old. That left no way for a person to correct the
-- name on something they had shared, and no way for the Mac that made it to
-- publish a new version of it to the people who already had it.
--
-- `revision` counts the versions. It goes up when the share changes, and
-- every installed copy remembers the revision it has, so it can tell whether
-- it is behind.
--
-- `edit_key` is the hash of the capability that lets its holder publish a
-- new version. The capability itself never leaves the Mac that made the
-- share — only the hash is here, so a copy of this table is not a key to
-- anybody's work.
--
-- `admin_edited` says the name and the author were corrected here. A
-- creator's later upload keeps those corrections rather than putting the
-- old words back.
--
-- The shares that already exist have no edit key. Their makers did not ask
-- for one, so nobody can update them: the app makes a new share instead,
-- and the old link keeps working.
ALTER TABLE shares ADD COLUMN revision INTEGER NOT NULL DEFAULT 1;
ALTER TABLE shares ADD COLUMN edit_key TEXT;
ALTER TABLE shares ADD COLUMN admin_edited INTEGER NOT NULL DEFAULT 0;
