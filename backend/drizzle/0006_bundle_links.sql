-- Bundle share links: 1 token agrega N assets via junction table.
-- Idempotente: safe re-apply.
BEGIN;

-- 1. share_link ganha flag + denorm count
ALTER TABLE share_link ADD COLUMN IF NOT EXISTS is_bundle boolean NOT NULL DEFAULT false;
ALTER TABLE share_link ADD COLUMN IF NOT EXISTS bundle_asset_count integer;

-- CHECK: bundle_asset_count obrigatório quando is_bundle, NULL quando não
DO $$
BEGIN
  ALTER TABLE share_link
    ADD CONSTRAINT share_link_bundle_count_check
    CHECK (
      (is_bundle = true  AND bundle_asset_count IS NOT NULL AND bundle_asset_count > 0)
      OR
      (is_bundle = false AND bundle_asset_count IS NULL)
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 2. Junction table. upload_job_id is the idempotency key — each presigned
-- slot in the bundle gets exactly one row, even when two slots dedup to the
-- same asset (e.g. user dropped the same file twice). asset_id may repeat;
-- (share_link_id, upload_job_id) is the unique pair.
CREATE TABLE IF NOT EXISTS bundle_asset (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  share_link_id uuid NOT NULL REFERENCES share_link(id) ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES asset(id),
  upload_job_id uuid NOT NULL REFERENCES upload_job(id),
  display_order integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

-- Lookup por bundle (renderiza /b/{token})
CREATE INDEX IF NOT EXISTS bundle_asset_link_order_idx
  ON bundle_asset (share_link_id, display_order);

-- Lookup reverso: este asset está em quais bundles? (precisa pra deletion safety)
CREATE INDEX IF NOT EXISTS bundle_asset_asset_idx
  ON bundle_asset (asset_id);

-- Garante display_order único dentro do bundle
CREATE UNIQUE INDEX IF NOT EXISTS bundle_asset_link_order_unique
  ON bundle_asset (share_link_id, display_order);

-- Idempotência: retry de /complete não duplica row da mesma slot.
CREATE UNIQUE INDEX IF NOT EXISTS bundle_asset_link_job_unique
  ON bundle_asset (share_link_id, upload_job_id);

COMMIT;
