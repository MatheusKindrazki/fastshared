-- Tier 2: multipart uploads. Presign stashes the R2 uploadId so /complete can
-- pass it (with the collected ETags) to CompleteMultipartUpload, and the abort
-- endpoint can hand it to AbortMultipartUpload. Idempotent — safe to re-apply.

BEGIN;

ALTER TABLE upload_job ADD COLUMN IF NOT EXISTS multipart_upload_id text;

COMMIT;
