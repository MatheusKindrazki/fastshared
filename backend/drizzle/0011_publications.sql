CREATE TABLE publication (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  owner_user_id uuid REFERENCES "user"(id) ON DELETE SET NULL,
  owner_device_id uuid NOT NULL REFERENCES device(id),
  title text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','expired','revoked','suspended','deleted')),
  current_version_id uuid,
  expires_at timestamptz,
  notify_on_open boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX publication_owner_user_idx ON publication(owner_user_id);
CREATE INDEX publication_owner_device_idx ON publication(owner_device_id);
CREATE INDEX publication_expiry_idx ON publication(status, expires_at);

CREATE TABLE publication_version (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid NOT NULL REFERENCES publication(id) ON DELETE CASCADE,
  number integer NOT NULL CHECK (number > 0),
  kind text NOT NULL CHECK (kind IN ('site','pdf','file')),
  entry_path text,
  file_count integer NOT NULL DEFAULT 0,
  total_bytes bigint NOT NULL DEFAULT 0,
  upload_key text NOT NULL,
  upload_size_bytes bigint NOT NULL,
  upload_content_type text NOT NULL,
  state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','ready','failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT publication_version_number_unique UNIQUE (publication_id, number)
);
ALTER TABLE publication ADD CONSTRAINT publication_current_version_fk FOREIGN KEY (current_version_id) REFERENCES publication_version(id);

CREATE TABLE publication_file (
  version_id uuid NOT NULL REFERENCES publication_version(id) ON DELETE CASCADE,
  path text NOT NULL,
  storage_key text NOT NULL,
  content_type text NOT NULL,
  size_bytes bigint NOT NULL,
  CONSTRAINT publication_file_version_path_pk PRIMARY KEY (version_id, path)
);

CREATE TABLE publication_open (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid NOT NULL REFERENCES publication(id) ON DELETE CASCADE,
  version_id uuid NOT NULL REFERENCES publication_version(id) ON DELETE CASCADE,
  visitor_hash text NOT NULL,
  opened_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX publication_open_dedupe_idx ON publication_open(publication_id, version_id, visitor_hash, opened_at);

CREATE TABLE publication_open_claim (
  publication_id uuid NOT NULL REFERENCES publication(id) ON DELETE CASCADE,
  version_id uuid NOT NULL REFERENCES publication_version(id) ON DELETE CASCADE,
  visitor_hash text NOT NULL,
  last_opened_at timestamptz NOT NULL,
  CONSTRAINT publication_open_claim_pk PRIMARY KEY (publication_id, version_id, visitor_hash)
);

CREATE TABLE publication_abuse_report (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid NOT NULL REFERENCES publication(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (reason IN ('phishing','malware','spam','other')),
  ip_hash text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX publication_abuse_report_recent_idx ON publication_abuse_report(publication_id, created_at);

CREATE TABLE entitlement (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  source text NOT NULL CHECK (source IN ('iap','paddle')),
  external_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('active','past_due','canceled','expired')),
  current_period_end timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT entitlement_source_external_unique UNIQUE (source, external_id)
);
CREATE INDEX entitlement_user_idx ON entitlement(user_id);
