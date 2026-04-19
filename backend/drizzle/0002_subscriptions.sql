-- FastShared Pro subscriptions.
--
-- Apple's App Store Server API identifies a subscription by
-- `original_transaction_id` — stable across renewals, restores, and family
-- sharing transfers. `latest_transaction_id` is the most recent event ID
-- and moves forward as renewals / refunds land. We upsert rows keyed on
-- `apple_original_transaction_id` and treat the partial unique index on
-- `(device_id) WHERE status = 'active'` as the one-active-sub-per-device
-- invariant; history rows remain, only one row is active at a time.

BEGIN;

CREATE TABLE IF NOT EXISTS subscription (
  id                                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id                         uuid NOT NULL
    REFERENCES device(id) ON DELETE RESTRICT,
  apple_original_transaction_id     text NOT NULL UNIQUE,
  tier                              text NOT NULL
    CHECK (tier IN ('monthly','annual','lifetime')),
  status                            text NOT NULL
    CHECK (status IN ('active','expired','in_grace','in_billing_retry','revoked','refunded')),
  expires_at                        timestamptz,                   -- NULL for lifetime
  auto_renew_status                 boolean NOT NULL DEFAULT true,
  latest_transaction_id             text NOT NULL,
  raw_notification_payload          jsonb,
  created_at                        timestamptz NOT NULL DEFAULT now(),
  updated_at                        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS subscription_device_idx
  ON subscription (device_id);

-- Partial: at most one active subscription per device. History rows with
-- status in (expired, revoked, refunded, in_grace, in_billing_retry) stay.
CREATE UNIQUE INDEX IF NOT EXISTS subscription_active_per_device
  ON subscription (device_id)
  WHERE status = 'active';

COMMIT;
