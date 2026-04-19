-- FastShared initial schema.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE IF NOT EXISTS "user" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS device (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash text NOT NULL UNIQUE,
  platform text NOT NULL,
  app_version text NOT NULL,
  user_id uuid REFERENCES "user"(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asset (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_device_id uuid NOT NULL REFERENCES device(id),
  owner_user_id uuid REFERENCES "user"(id),
  bucket text NOT NULL,
  object_key text NOT NULL UNIQUE,
  content_type text NOT NULL,
  size_bytes bigint NOT NULL,
  sha256 text,
  original_filename text,
  status text NOT NULL CHECK (status IN ('pending','verified','failed','deleted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  verified_at timestamptz
);

CREATE INDEX IF NOT EXISTS asset_device_created_idx
  ON asset (owner_device_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS asset_dedup_per_device
  ON asset (owner_device_id, sha256)
  WHERE sha256 IS NOT NULL AND status <> 'deleted';

CREATE TABLE IF NOT EXISTS share_link (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  asset_id uuid NOT NULL REFERENCES asset(id),
  visibility text NOT NULL CHECK (visibility IN ('public','signed','password')),
  password_hash text,
  expires_at timestamptz,
  hits bigint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS share_link_asset_idx ON share_link (asset_id);

CREATE INDEX IF NOT EXISTS share_link_expires_idx
  ON share_link (expires_at) WHERE expires_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS upload_job (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id uuid NOT NULL REFERENCES device(id),
  asset_id uuid REFERENCES asset(id),
  client_job_id text NOT NULL,
  status text NOT NULL,
  error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (device_id, client_job_id)
);
