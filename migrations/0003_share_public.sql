-- Whether a share is in the public gallery.
--
-- Sharing a vibescape has always made a link anybody with it can open. The
-- gallery is different: it lists them, so a vibescape that is in it is
-- findable by anybody at all. The app asks — there is a tickbox in the share
-- sheet, on by default, and it says that the name and the author are public.
--
-- Zero for the shares that were made before the gallery existed: they were
-- never offered the choice, and publishing them without asking would be
-- putting somebody else's name on the front page of the site.
ALTER TABLE shares ADD COLUMN is_public INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS shares_is_public ON shares (is_public, created_at DESC);
