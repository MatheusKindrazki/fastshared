ALTER TABLE entitlement ADD COLUMN paddle_customer_id text;
ALTER TABLE entitlement ADD COLUMN last_event_at timestamptz;
CREATE INDEX entitlement_paddle_customer_idx ON entitlement(paddle_customer_id) WHERE source = 'paddle';

CREATE TABLE billing_event (
  event_id text PRIMARY KEY,
  event_type text NOT NULL,
  status text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'processed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);

CREATE TABLE email_login_token (
  token_hash text PRIMARY KEY,
  email citext NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX email_login_token_expiry_idx ON email_login_token(expires_at);
