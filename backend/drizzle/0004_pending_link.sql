-- Tier 1: optimistic short URL. Presign mints a share_link in `pending` state so
-- the client can copy the URL before bytes land; /complete flips it to `active`.
-- This migration is idempotent — safe to re-apply.

BEGIN;

-- 1. Relax the link_status CHECK constraint to allow 'pending'. The constraint
-- name is schema-dependent (Drizzle 0001 inlined it), so look it up first.
DO $$
DECLARE
  cname text;
BEGIN
  SELECT conname INTO cname
  FROM pg_constraint
  WHERE conrelid = 'share_link'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%link_status%';
  IF cname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE share_link DROP CONSTRAINT %I', cname);
  END IF;
END $$;

DO $$
BEGIN
  ALTER TABLE share_link
    ADD CONSTRAINT share_link_link_status_check
    CHECK (link_status IN ('pending', 'active', 'expired', 'revoked'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 2. Pending rows have no asset yet — the asset is created at /complete.
ALTER TABLE share_link ALTER COLUMN asset_id DROP NOT NULL;

-- 3. Carry the presign-time token on upload_job so /complete can flip the
-- right pending share_link row.
ALTER TABLE upload_job ADD COLUMN IF NOT EXISTS pending_share_link_token text;

-- 4. Fast path for the pending-link cleanup cron (stale pending > 1h).
CREATE INDEX IF NOT EXISTS share_link_pending_idx
  ON share_link (link_status, created_at)
  WHERE link_status = 'pending';

COMMIT;
