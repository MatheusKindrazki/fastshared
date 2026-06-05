import { eq, inArray, or, sql } from 'drizzle-orm';
import type { Db } from '~/db/client';
import { asset, device, shareLink, subscription, user } from '~/db/schema';
import { scheduleDeletion } from '~/services/assets';
import { log } from '~/lib/logger';

export type DeleteAccountResult =
  | {
      status: 'deleted';
      userId: string;
      assetsScheduled: number;
      linksRevoked: number;
      devicesUnlinked: number;
    }
  | { status: 'not_linked' }
  | { status: 'device_not_found' };

// Hard-deletes the whole Apple account behind a single device (App Store
// Guideline 5.1.1v). This affects EVERY device linked to the same user, not
// just the caller.
//
// FK SAFETY / ORDERING. The Neon HTTP driver is fetch-based and does not
// support interactive transactions, so we run sequential, individually
// idempotent statements in an order that never trips a foreign key:
//
//   1. revoke + schedule-delete each asset (no FK impact; pure data lifecycle)
//   2. delete subscription rows keyed by the user's devices
//   3. NULL out asset.owner_user_id for the user's assets   <-- critical
//   4. delete the user row last
//
// Step 3 is the load-bearing one: asset.owner_user_id references user.id with
// NO on-delete rule (NO ACTION / RESTRICT). Deleting the user while any asset
// still points at it via owner_user_id would raise a 23503 and abort the whole
// thing. We must orphan those assets onto owner_device_id first. Deleting the
// user (step 4) in turn fires device.user_id's ON DELETE SET NULL, orphaning —
// not dropping — every device so their uploads/history survive the grace
// window until the deletion jobs sweep them.
export async function deleteAccountForDevice(
  db: Db,
  deviceId: string,
): Promise<DeleteAccountResult> {
  const deviceRows = await db
    .select({ id: device.id, userId: device.userId })
    .from(device)
    .where(eq(device.id, deviceId))
    .limit(1);
  const current = deviceRows[0];
  if (!current) return { status: 'device_not_found' };
  if (!current.userId) return { status: 'not_linked' };
  const userId = current.userId;

  // Every device linked to the same Apple account — deletion is account-wide.
  const userDevices = await db
    .select({ id: device.id })
    .from(device)
    .where(eq(device.userId, userId));
  const deviceIds = userDevices.map((d) => d.id);

  // Assets owned by the user directly OR by any of their devices. distinct so a
  // row matched on both predicates isn't processed twice.
  const ownedAssets = await db
    .select({ id: asset.id })
    .from(asset)
    .where(
      deviceIds.length > 0
        ? or(eq(asset.ownerUserId, userId), inArray(asset.ownerDeviceId, deviceIds))
        : eq(asset.ownerUserId, userId),
    );
  const assetIds = [...new Set(ownedAssets.map((a) => a.id))];

  // 1. Revoke active/pending links and schedule immediate deletion per asset.
  // Per-asset try/catch so one bad row never strands the rest of the account.
  const now = new Date();
  let assetsScheduled = 0;
  let linksRevoked = 0;
  for (const assetId of assetIds) {
    try {
      // Count the links we're actually transitioning out of a live state for an
      // accurate `linksRevoked`, then collapse them all to revoked. Mirrors
      // softDeleteAsset: revoke by asset (re-revoking a dead link is a no-op).
      const liveLinks = await db
        .select({ id: shareLink.id, linkStatus: shareLink.linkStatus })
        .from(shareLink)
        .where(eq(shareLink.assetId, assetId));
      linksRevoked += liveLinks.filter(
        (l) => l.linkStatus === 'active' || l.linkStatus === 'pending',
      ).length;
      await db
        .update(shareLink)
        .set({ linkStatus: 'revoked', revokedAt: sql`now()` })
        .where(eq(shareLink.assetId, assetId));
      await scheduleDeletion(db, assetId, now);
      assetsScheduled += 1;
    } catch (err) {
      log.warn({
        msg: 'account_deletion_asset_failed',
        userId,
        assetId,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // 2. Drop subscriptions for the user's devices (subscription.device_id has no
  // cascade; clear it before the device rows get orphaned).
  if (deviceIds.length > 0) {
    await db.delete(subscription).where(inArray(subscription.deviceId, deviceIds));
  }

  // 3. Orphan the user's assets off owner_user_id BEFORE deleting the user —
  // owner_user_id has no ON DELETE rule, so this prevents an FK violation.
  await db.update(asset).set({ ownerUserId: null }).where(eq(asset.ownerUserId, userId));

  // 4. Delete the user row last; device.user_id ON DELETE SET NULL unlinks all
  // of the account's devices in the same statement.
  await db.delete(user).where(eq(user.id, userId));

  return {
    status: 'deleted',
    userId,
    assetsScheduled,
    linksRevoked,
    devicesUnlinked: deviceIds.length,
  };
}
