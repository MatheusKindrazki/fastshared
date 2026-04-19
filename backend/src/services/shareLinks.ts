import { and, eq, sql } from 'drizzle-orm';
import type { Db } from '~/db/client';
import { asset, shareLink, type ShareLink, type NewShareLink } from '~/db/schema';
import { generateToken, TOKEN_LENGTH } from '~/lib/tokens';

export type Visibility = 'public' | 'signed' | 'password';

export interface CreateShareLinkArgs {
  db: Db;
  assetId: string;
  retentionPolicy: string;
  expiresAt: Date;
  visibility?: Visibility;
  passwordHash?: string | null;
  maxAccessCount?: number | null;
  token?: string;
}

export async function createShareLink(args: CreateShareLinkArgs): Promise<ShareLink> {
  const maxAttempts = 5;
  let length = TOKEN_LENGTH;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const token = args.token ?? generateToken(length);
    try {
      const values: NewShareLink = {
        token,
        assetId: args.assetId,
        visibility: args.visibility ?? 'signed',
        expiresAt: args.expiresAt,
        retentionPolicy: args.retentionPolicy,
        linkStatus: 'active',
        passwordHash: args.passwordHash ?? null,
        maxAccessCount: args.maxAccessCount ?? null,
      };
      const [row] = await args.db.insert(shareLink).values(values).returning();
      if (row) return row;
    } catch (err) {
      if (!isUniqueViolation(err)) throw err;
      // Token was explicitly provided — don't silently rewrite it, surface the conflict.
      if (args.token) throw err;
      // After a few same-length collisions, widen so we walk out of any bad entropy pocket.
      if (attempt >= 2) length = Math.max(length, 26);
    }
  }
  throw new Error('share_link token collision retries exhausted');
}

export async function findByToken(db: Db, token: string): Promise<ShareLink | null> {
  const rows = await db.select().from(shareLink).where(eq(shareLink.token, token)).limit(1);
  return rows[0] ?? null;
}

export async function revokeByToken(
  db: Db,
  token: string,
  deviceId: string,
): Promise<{ status: 'ok' | 'not_found' | 'forbidden'; link: ShareLink | null }> {
  // Resolve the link + owning device in one round trip so we can 403 cleanly.
  const rows = await db
    .select({
      id: shareLink.id,
      token: shareLink.token,
      assetId: shareLink.assetId,
      linkStatus: shareLink.linkStatus,
      ownerDeviceId: asset.ownerDeviceId,
    })
    .from(shareLink)
    .innerJoin(asset, eq(asset.id, shareLink.assetId))
    .where(eq(shareLink.token, token))
    .limit(1);
  const found = rows[0];
  if (!found) return { status: 'not_found', link: null };
  if (found.ownerDeviceId !== deviceId) return { status: 'forbidden', link: null };

  const [updated] = await db
    .update(shareLink)
    .set({ linkStatus: 'revoked', revokedAt: sql`now()` })
    .where(eq(shareLink.id, found.id))
    .returning();
  return { status: 'ok', link: updated ?? null };
}

export async function markExpiredByAssetId(db: Db, assetId: string): Promise<void> {
  await db
    .update(shareLink)
    .set({ linkStatus: 'expired' })
    .where(and(eq(shareLink.assetId, assetId), eq(shareLink.linkStatus, 'active')));
}

export async function markExpiredByToken(db: Db, token: string): Promise<void> {
  await db
    .update(shareLink)
    .set({ linkStatus: 'expired' })
    .where(and(eq(shareLink.token, token), eq(shareLink.linkStatus, 'active')));
}

// Single UPDATE keeps the hot redirect path to one round trip.
export async function incrementAccess(db: Db, token: string): Promise<void> {
  await db
    .update(shareLink)
    .set({
      accessCount: sql`${shareLink.accessCount} + 1`,
      lastAccessedAt: sql`now()`,
      hits: sql`${shareLink.hits} + 1`,
    })
    .where(eq(shareLink.token, token));
}

function isUniqueViolation(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false;
  const e = err as { code?: string; message?: string };
  if (e.code === '23505') return true;
  if (typeof e.message === 'string' && /duplicate key|unique constraint/i.test(e.message))
    return true;
  return false;
}
