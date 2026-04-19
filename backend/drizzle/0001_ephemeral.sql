-- FastShared ephemeral-first lifecycle.
--
-- Assumptions: only 0000_init has ever been applied; no production data exists.
-- The migration is written to be idempotent on an empty DB (backfills happen
-- before setting NOT NULL).

BEGIN;

--
-- asset: rename object_key -> storage_key, add deletion bookkeeping columns.
--
ALTER TABLE asset RENAME COLUMN object_key TO storage_key;

ALTER TABLE asset
  ADD COLUMN deleted_at          timestamptz,
  ADD COLUMN delete_after        timestamptz,
  ADD COLUMN deletion_status     text NOT NULL DEFAULT 'pending'
    CHECK (deletion_status IN ('pending','scheduled','deleted','failed')),
  ADD COLUMN deletion_attempts   integer NOT NULL DEFAULT 0,
  ADD COLUMN deletion_last_error text;

-- Backfill delete_after so the NOT NULL tightening is safe on a dirty-empty DB.
UPDATE asset
   SET delete_after = now() + interval '25 hours'
 WHERE delete_after IS NULL;

ALTER TABLE asset ALTER COLUMN delete_after SET NOT NULL;

-- Replace the dedup unique index so it only matches live assets.
DROP INDEX IF EXISTS asset_dedup_per_device;

CREATE UNIQUE INDEX asset_dedup_per_device
  ON asset (owner_device_id, sha256)
  WHERE sha256 IS NOT NULL
    AND deleted_at IS NULL
    AND status <> 'deleted';

--
-- share_link: rename slug -> token, tighten expires_at, add status + retention columns.
--
ALTER TABLE share_link RENAME COLUMN slug TO token;

-- Backfill expires_at defensively before making it NOT NULL (empty DB in MVP).
UPDATE share_link
   SET expires_at = now() + interval '1 day'
 WHERE expires_at IS NULL;

ALTER TABLE share_link ALTER COLUMN expires_at SET NOT NULL;

ALTER TABLE share_link
  ADD COLUMN link_status        text NOT NULL DEFAULT 'active'
    CHECK (link_status IN ('active','expired','revoked')),
  ADD COLUMN retention_policy   text,
  ADD COLUMN revoked_at         timestamptz,
  ADD COLUMN last_accessed_at   timestamptz,
  ADD COLUMN access_count       bigint NOT NULL DEFAULT 0,
  ADD COLUMN max_access_count   bigint;

UPDATE share_link
   SET retention_policy = 'oneDay'
 WHERE retention_policy IS NULL;

ALTER TABLE share_link ALTER COLUMN retention_policy SET NOT NULL;

DROP INDEX IF EXISTS share_link_expires_idx;

CREATE INDEX share_link_active_expires_idx
  ON share_link (expires_at)
  WHERE link_status = 'active';

--
-- upload_job: carry ephemeral intent from presign to complete.
--
ALTER TABLE upload_job
  ADD COLUMN retention_policy text,
  ADD COLUMN expires_at       timestamptz,
  ADD COLUMN delete_after     timestamptz;

--
-- deletion_job: app-level retention worker queue.
--
CREATE TABLE deletion_job (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id      uuid NOT NULL REFERENCES asset(id) ON DELETE CASCADE,
  scheduled_for timestamptz NOT NULL,
  status        text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','running','done','failed')),
  attempts      integer NOT NULL DEFAULT 0,
  last_error    text,
  locked_at     timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- At most one active (pending|running) job per asset.
CREATE UNIQUE INDEX deletion_job_active_per_asset
  ON deletion_job (asset_id)
  WHERE status IN ('pending','running');

-- Fast due-job pick for the /1-minute cron.
CREATE INDEX deletion_job_due_idx
  ON deletion_job (scheduled_for)
  WHERE status = 'pending';

COMMIT;
