-- FastShared Sign in with Apple.
--
-- Adds account-level columns to "user" and wires device.user_id with an
-- ON DELETE SET NULL FK so a user deletion orphans their devices rather
-- than cascading into their upload history.
--
-- `apple_user_id` is the sub claim Apple hands us on the identity token.
-- It's the ONLY stable identifier across sign-ins — email may be Apple
-- Private Relay or omitted entirely on subsequent authorizations.

BEGIN;

--
-- "user": add Apple linkage + profile fields and track updates.
--
ALTER TABLE "user"
  ADD COLUMN IF NOT EXISTS apple_user_id text,
  ADD COLUMN IF NOT EXISTS full_name     text,
  ADD COLUMN IF NOT EXISTS updated_at    timestamptz NOT NULL DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS user_apple_user_id_unique
  ON "user" (apple_user_id);

--
-- device.user_id: replace the default RESTRICT FK with ON DELETE SET NULL
-- so removing a user doesn't brick their anonymous device rows, and add an
-- index for the user → devices lookup.
--
ALTER TABLE device DROP CONSTRAINT IF EXISTS device_user_id_fkey;

ALTER TABLE device
  ADD CONSTRAINT device_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS device_user_id_idx
  ON device (user_id);

COMMIT;
