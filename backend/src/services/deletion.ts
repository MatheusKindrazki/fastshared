import { eq, sql } from 'drizzle-orm';
import type { Env } from '~/env';
import { createDb, type Db } from '~/db/client';
import { asset, deletionJob } from '~/db/schema';
import { deleteObject } from '~/services/r2';
import { log } from '~/lib/logger';

const BATCH_SIZE = 50;
const MAX_ATTEMPTS = 8;
// Exponential backoff: 120s * 2^(attempts-1), capped at 2h, plus ±10% jitter.
const BACKOFF_BASE_SECONDS = 120;
const BACKOFF_CAP_SECONDS = 7200;

interface ClaimedJob {
  id: string;
  assetId: string;
  attempts: number;
  storageKey: string;
}

export async function runDueDeletionJobs(env: Env, ctx: ExecutionContext): Promise<void> {
  void ctx;
  const db = createDb(env.DATABASE_URL);
  const claimed = await claimDueJobs(db);
  if (claimed.length === 0) return;

  log.info({ msg: 'deletion_batch_start', count: claimed.length });

  for (const job of claimed) {
    try {
      await deleteObject({ env, key: job.storageKey });
      await markJobDone(db, job);
      log.info({ msg: 'deletion_succeeded', jobId: job.id, assetId: job.assetId });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (job.attempts >= MAX_ATTEMPTS) {
        await markJobFailed(db, job, message);
        log.error({
          msg: 'deletion_giving_up',
          jobId: job.id,
          assetId: job.assetId,
          attempts: job.attempts,
          error: message,
        });
      } else {
        const nextRun = computeNextRun(job.attempts);
        await requeueJob(db, job, nextRun, message);
        log.warn({
          msg: 'deletion_requeued',
          jobId: job.id,
          assetId: job.assetId,
          attempts: job.attempts,
          nextRun: nextRun.toISOString(),
          error: message,
        });
      }
    }
  }
}

async function claimDueJobs(db: Db): Promise<ClaimedJob[]> {
  // Single atomic CTE: lock the due rows with SKIP LOCKED, flip their status,
  // and return joined storage_key so the worker has everything in hand.
  const result = await db.execute<{
    id: string;
    asset_id: string;
    attempts: number;
    storage_key: string;
  }>(sql`
    WITH due AS (
      SELECT id
        FROM deletion_job
       WHERE status = 'pending'
         AND scheduled_for <= now()
       ORDER BY scheduled_for
       LIMIT ${BATCH_SIZE}
       FOR UPDATE SKIP LOCKED
    ), claimed AS (
      UPDATE deletion_job dj
         SET status = 'running',
             locked_at = now(),
             attempts = dj.attempts + 1,
             updated_at = now()
        FROM due
       WHERE dj.id = due.id
       RETURNING dj.id, dj.asset_id, dj.attempts
    )
    SELECT c.id, c.asset_id, c.attempts, a.storage_key
      FROM claimed c
      JOIN asset a ON a.id = c.asset_id
  `);
  // Neon's drizzle execute returns a typed rows array (shape depends on driver).
  const rows = extractRows(result);
  return rows.map((r) => ({
    id: String(r.id),
    assetId: String(r.asset_id),
    attempts: Number(r.attempts),
    storageKey: String(r.storage_key),
  }));
}

async function markJobDone(db: Db, job: ClaimedJob): Promise<void> {
  await db
    .update(deletionJob)
    .set({ status: 'done', lastError: null, updatedAt: sql`now()` })
    .where(eq(deletionJob.id, job.id));
  await db
    .update(asset)
    .set({
      status: 'deleted',
      deletedAt: sql`now()`,
      deletionStatus: 'deleted',
      deletionAttempts: job.attempts,
      deletionLastError: null,
    })
    .where(eq(asset.id, job.assetId));
}

async function markJobFailed(db: Db, job: ClaimedJob, error: string): Promise<void> {
  await db
    .update(deletionJob)
    .set({ status: 'failed', lastError: error, updatedAt: sql`now()` })
    .where(eq(deletionJob.id, job.id));
  await db
    .update(asset)
    .set({
      deletionStatus: 'failed',
      deletionAttempts: job.attempts,
      deletionLastError: error,
    })
    .where(eq(asset.id, job.assetId));
}

async function requeueJob(db: Db, job: ClaimedJob, nextRun: Date, error: string): Promise<void> {
  await db
    .update(deletionJob)
    .set({
      status: 'pending',
      scheduledFor: nextRun,
      lastError: error,
      lockedAt: null,
      updatedAt: sql`now()`,
    })
    .where(eq(deletionJob.id, job.id));
  await db
    .update(asset)
    .set({
      deletionStatus: 'scheduled',
      deletionAttempts: job.attempts,
      deletionLastError: error,
    })
    .where(eq(asset.id, job.assetId));
}

function computeNextRun(attempts: number): Date {
  const exponent = Math.max(0, attempts - 1);
  const raw = BACKOFF_BASE_SECONDS * Math.pow(2, exponent);
  const capped = Math.min(raw, BACKOFF_CAP_SECONDS);
  const jitter = capped * (Math.random() * 0.2 - 0.1);
  const delaySeconds = Math.max(1, Math.round(capped + jitter));
  return new Date(Date.now() + delaySeconds * 1000);
}

function extractRows(
  result: unknown,
): Array<{ id: unknown; asset_id: unknown; attempts: unknown; storage_key: unknown }> {
  if (Array.isArray(result)) return result as never;
  if (result && typeof result === 'object' && 'rows' in result) {
    const rows = (result as { rows: unknown }).rows;
    if (Array.isArray(rows)) return rows as never;
  }
  return [];
}
