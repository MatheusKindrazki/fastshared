-- Adds an explicit backend verification state for App Store Server API checks.
-- `grace` is a short-lived 24h fallback after a locally-valid Apple JWS when
-- the authoritative App Store Server API is temporarily unavailable.

BEGIN;

ALTER TABLE subscription
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'verified';

ALTER TABLE subscription
  ADD COLUMN IF NOT EXISTS verification_grace_until timestamptz;

ALTER TABLE subscription
  DROP CONSTRAINT IF EXISTS subscription_verification_status_check;

ALTER TABLE subscription
  ADD CONSTRAINT subscription_verification_status_check
  CHECK (verification_status IN ('verified', 'grace'));

CREATE INDEX IF NOT EXISTS subscription_verification_grace_idx
  ON subscription (verification_grace_until)
  WHERE verification_status = 'grace';

COMMIT;
