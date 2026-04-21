import { sql } from 'drizzle-orm';
import type { Env } from '~/env';
import { createDb } from '~/db/client';
import { log } from '~/lib/logger';

const STUCK_LOCK_MINUTES = 10;

export async function runReconciliation(env: Env): Promise<void> {
  const db = createDb(env.DATABASE_URL);

  // 1) Flip active links whose expiry has passed. Cheap bulk update.
  const expired = await db.execute<{ id: string }>(sql`
    UPDATE share_link
       SET link_status = 'expired'
     WHERE link_status = 'active'
       AND expires_at < now()
    RETURNING id
  `);

  // 2) Enqueue a deletion job for any asset past its delete_after grace window
  //    that doesn't already have an active job. Partial unique index enforces
  //    idempotency; ON CONFLICT makes the insert safe under races.
  const enqueued = await db.execute<{ id: string }>(sql`
    INSERT INTO deletion_job (asset_id, scheduled_for, status)
    SELECT a.id, now(), 'pending'
      FROM asset a
     WHERE a.delete_after < now()
       AND a.deleted_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM deletion_job dj
          WHERE dj.asset_id = a.id
            AND dj.status IN ('pending','running')
       )
    ON CONFLICT DO NOTHING
    RETURNING id
  `);

  // 3) Requeue stuck 'running' jobs whose lock is older than the threshold —
  //    almost certainly a worker that died mid-run.
  const requeued = await db.execute<{ id: string }>(sql`
    UPDATE deletion_job
       SET status = 'pending',
           locked_at = NULL,
           updated_at = now()
     WHERE status = 'running'
       AND locked_at < now() - (${STUCK_LOCK_MINUTES} || ' minutes')::interval
    RETURNING id
  `);

  // 4) Sweep stale pending share_links. Two cohorts:
  //    a) Single (is_bundle=false) OR bundle with zero junction rows, older
  //       than 1h: nothing landed. Drop the row outright.
  //    b) Bundle with partial junction rows older than 24h: caller gave up
  //       mid-batch. Mark expired so /b/:token returns 410 — the deletion
  //       cron picks up the asset bytes via their own delete_after window.
  const cleaned = await db.execute<{ id: string }>(sql`
    DELETE FROM share_link
     WHERE link_status = 'pending'
       AND created_at < now() - interval '1 hour'
       AND (
         is_bundle = false
         OR NOT EXISTS (
           SELECT 1 FROM bundle_asset ba WHERE ba.share_link_id = share_link.id
         )
       )
    RETURNING id
  `);
  const partialExpired = await db.execute<{ id: string }>(sql`
    UPDATE share_link
       SET link_status = 'expired'
     WHERE link_status = 'pending'
       AND is_bundle = true
       AND created_at < now() - interval '24 hours'
       AND EXISTS (
         SELECT 1 FROM bundle_asset ba WHERE ba.share_link_id = share_link.id
       )
    RETURNING id
  `);

  log.info({
    msg: 'reconciliation_done',
    expired: rowCount(expired),
    enqueued: rowCount(enqueued),
    requeued: rowCount(requeued),
    pendingCleaned: rowCount(cleaned),
    bundlesPartialExpired: rowCount(partialExpired),
  });
}

function rowCount(result: unknown): number {
  if (Array.isArray(result)) return result.length;
  if (result && typeof result === 'object') {
    const r = result as { rowCount?: number; rows?: unknown[] };
    if (typeof r.rowCount === 'number') return r.rowCount;
    if (Array.isArray(r.rows)) return r.rows.length;
  }
  return 0;
}
