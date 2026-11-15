import { eq } from 'drizzle-orm';
import { createDb } from '~/db/client';
import { publication } from '~/db/schema';
import type { Env } from '~/env';
import {
  findActiveEntitlementForDevice,
  findActiveProForDevice,
  isProForAllUsersEnabled,
  parseAppleUserAllowList,
} from '~/services/subscriptions';

const DAY = 86400_000;

export function nextPublicationState(
  row: {
    status: string;
    ownerUserId: string | null;
    createdAt: Date;
    expiresAt: Date | null;
    updatedAt: Date;
  },
  isPro: boolean,
  now: Date,
): { status?: string; expiresAt?: Date | null; deletePrefix?: boolean } {
  if (row.status === 'revoked') return { deletePrefix: true };
  if (row.status === 'deleted' || row.status === 'suspended') return {};
  if (row.status === 'expired') {
    if (isPro && row.ownerUserId) return { status: 'active', expiresAt: null };
    return row.expiresAt && now.getTime() >= row.expiresAt.getTime() + DAY
      ? { deletePrefix: true }
      : {};
  }
  if (isPro && row.ownerUserId) return row.expiresAt ? { expiresAt: null } : {};
  if (!row.expiresAt) return { expiresAt: new Date(now.getTime() + 30 * DAY) };
  if (!row.ownerUserId && row.expiresAt.getTime() > row.createdAt.getTime() + 7 * DAY)
    return { expiresAt: new Date(row.createdAt.getTime() + 7 * DAY) };
  if (row.expiresAt <= now) return { status: 'expired' };
  return {};
}

async function deletePrefix(env: Env, prefix: string): Promise<void> {
  let cursor: string | undefined;
  for (;;) {
    const page = await env.PUBLICATIONS.list({
      prefix,
      ...(cursor ? { cursor } : {}),
      limit: 1000,
    });
    if (page.objects.length) await env.PUBLICATIONS.delete(page.objects.map((o) => o.key));
    if (page.truncated && page.cursor) cursor = page.cursor;
    else break;
  }
}

export async function deletePublicationPrefix(env: Env, id: string): Promise<void> {
  await deletePrefix(env, `pub/${id}/`);
}

export async function deletePublicationVersionPrefix(
  env: Env,
  id: string,
  version: number,
): Promise<void> {
  await deletePrefix(env, `pub/${id}/v${version}/`);
}

export async function runPublicationLifecycle(env: Env, now = new Date()): Promise<void> {
  const db = createDb(env.DATABASE_URL);
  const rows = await db.select().from(publication);
  for (const row of rows) {
    try {
      const isPro =
        row.ownerUserId !== null &&
        ((await findActiveEntitlementForDevice(db, row.ownerDeviceId)) ||
          !!(await findActiveProForDevice(
            db,
            row.ownerDeviceId,
            parseAppleUserAllowList(env.DEV_PRO_APPLE_USER_IDS, env.BETA_UNLIMITED_APPLE_USER_IDS),
            { proForAllUsers: isProForAllUsersEnabled(env.PRO_FOR_ALL_USERS) },
          )));
      const next = nextPublicationState(row, isPro, now);
      if (next.status || next.expiresAt !== undefined) {
        await db
          .update(publication)
          .set({
            ...(next.status ? { status: next.status } : {}),
            ...(next.expiresAt !== undefined ? { expiresAt: next.expiresAt } : {}),
            updatedAt: now,
          })
          .where(eq(publication.id, row.id));
        await env.RATE_LIMIT.delete(`pub:cache:${row.slug}`);
      }
      if (next.deletePrefix) {
        await deletePublicationPrefix(env, row.id);
        await db
          .update(publication)
          .set({ status: 'deleted', deletedAt: now, updatedAt: now })
          .where(eq(publication.id, row.id));
        await env.RATE_LIMIT.delete(`pub:cache:${row.slug}`);
      }
    } catch {
      // Keep the row eligible for the next cron tick. Other publications continue.
    }
  }
}
