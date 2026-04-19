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

  log.info({
    msg: 'reconciliation_done',
    expired: rowCount(expired),
    enqueued: rowCount(enqueued),
    requeued: rowCount(requeued),
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
