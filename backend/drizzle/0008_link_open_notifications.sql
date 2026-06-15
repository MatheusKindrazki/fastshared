ALTER TABLE "device"
  ADD COLUMN IF NOT EXISTS "apns_token" text,
  ADD COLUMN IF NOT EXISTS "apns_environment" text,
  ADD COLUMN IF NOT EXISTS "apns_updated_at" timestamp with time zone;

ALTER TABLE "share_link"
  ADD COLUMN IF NOT EXISTS "notify_on_open" boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS "device_apns_token_idx"
  ON "device" ("apns_token")
  WHERE "apns_token" IS NOT NULL;
