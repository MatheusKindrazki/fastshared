import { and, eq, isNull, sql } from 'drizzle-orm';
import type { Db } from '~/db/client';
import { asset, deletionJob, shareLink, type Asset, type NewAsset } from '~/db/schema';

export async function createAsset(db: Db, values: NewAsset): Promise<Asset> {
  const [inserted] = await db.insert(asset).values(values).returning();
  if (!inserted) throw new Error('asset insert returned no rows');
  return inserted;
}

// Dedup lookup: only matches live, verified assets that still have a live share
// link. Once something is expired/revoked/deleted we always want a fresh upload.
export async function findLiveAssetBySha256AndDevice(
  db: Db,
  deviceId: string,
  sha256: string,
): Promise<Asset | null> {
  const rows = await db
    .select()
    .from(asset)
    .where(
      and(
        eq(asset.ownerDeviceId, deviceId),
        eq(asset.sha256, sha256),
        eq(asset.status, 'verified'),
        isNull(asset.deletedAt),
        sql`${asset.deleteAfter} > now()`,
      ),
    )
    .limit(1);
  return rows[0] ?? null;
}

// Back-compat shim — older code paths can still ask "do we have this hash".
export async function findAssetBySha256AndDevice(
  db: Db,
  deviceId: string,
  sha256: string,
): Promise<Asset | null> {
  return findLiveAssetBySha256AndDevice(db, deviceId, sha256);
}

export async function softDeleteAsset(
  db: Db,
  assetId: string,
  ownerDeviceId: string,
): Promise<boolean> {
  const updated = await db
    .update(asset)
    .set({ status: 'deleted' })
    .where(and(eq(asset.id, assetId), eq(asset.ownerDeviceId, ownerDeviceId)))
    .returning({ id: asset.id });
  if (updated.length === 0) return false;
  await db
    .update(shareLink)
    .set({ linkStatus: 'revoked', revokedAt: sql`now()` })
    .where(eq(shareLink.assetId, assetId));
  return true;
}

export async function findAssetForDevice(
  db: Db,
  assetId: string,
  ownerDeviceId: string,
): Promise<Asset | null> {
  const rows = await db
    .select()
    .from(asset)
    .where(and(eq(asset.id, assetId), eq(asset.ownerDeviceId, ownerDeviceId)))
    .limit(1);
  return rows[0] ?? null;
}

// Idempotent: the partial unique index on deletion_job (active-per-asset) makes
// double-insert during a race a no-op via ON CONFLICT DO NOTHING.
export async function scheduleDeletion(db: Db, assetId: string, when: Date): Promise<void> {
  await db
    .insert(deletionJob)
    .values({ assetId, scheduledFor: when, status: 'pending' })
    .onConflictDoNothing();
}

export async function markAssetDeleted(db: Db, assetId: string): Promise<void> {
  await db
    .update(asset)
    .set({
      status: 'deleted',
      deletedAt: sql`now()`,
      deletionStatus: 'deleted',
    })
    .where(eq(asset.id, assetId));
}
