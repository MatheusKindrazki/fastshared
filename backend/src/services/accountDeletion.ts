import { and, eq, inArray, or, sql } from 'drizzle-orm';
import type { Db } from '~/db/client';
import { asset, deletionJob, device, shareLink, subscription, user } from '~/db/schema';

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
//   1. revoke + schedule-delete every asset in bulk (no FK impact; pure data lifecycle)
//   2. delete subscription rows keyed by the user's devices
//   3. NULL out asset.owner_user_id for the user's assets   <-- critical
//   4. NULL out device.user_id for the user's devices
//   5. delete the user row last
//
// Step 3 is the load-bearing one: asset.owner_user_id references user.id with
// NO on-delete rule (NO ACTION / RESTRICT). Deleting the user while any asset
// still points at it via owner_user_id would raise a 23503 and abort the whole
// thing. We must orphan those assets onto owner_device_id first. Step 4 is
// deliberately explicit even though the intended FK is ON DELETE SET NULL:
// production schemas can lag migrations, and account deletion must not depend
// on that FK action to succeed.
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

  // 1. Revoke active/pending links and schedule immediate deletion for every
  // owned asset. Keep this bulk-only: real accounts can have hundreds of
  // assets, and doing 2-3 Neon HTTP round-trips per asset makes the Worker
  // request time out before the user row is deleted.
  const now = new Date();
  let linksRevoked = 0;
  if (assetIds.length > 0) {
    const liveLinks = await db
      .select({ id: shareLink.id })
      .from(shareLink)
      .where(
        and(
          inArray(shareLink.assetId, assetIds),
          inArray(shareLink.linkStatus, ['active', 'pending']),
        ),
      );
    linksRevoked = liveLinks.length;

    await db
      .update(shareLink)
      .set({ linkStatus: 'revoked', revokedAt: sql`now()` })
      .where(inArray(shareLink.assetId, assetIds));

    await db
      .insert(deletionJob)
      .values(assetIds.map((assetId) => ({ assetId, scheduledFor: now, status: 'pending' })))
      .onConflictDoNothing();
  }

  // 2. Drop subscriptions for the user's devices (subscription.device_id has no
  // cascade; clear it before the device rows get orphaned).
  if (deviceIds.length > 0) {
    await db.delete(subscription).where(inArray(subscription.deviceId, deviceIds));
  }

  // 3. Orphan the user's assets off owner_user_id BEFORE deleting the user —
  // owner_user_id has no ON DELETE rule, so this prevents an FK violation.
  await db.update(asset).set({ ownerUserId: null }).where(eq(asset.ownerUserId, userId));

  // 4. Unlink devices explicitly before deleting the user. This keeps deletion
  // robust even if an older production FK is still RESTRICT instead of
  // ON DELETE SET NULL.
  if (deviceIds.length > 0) {
    await db.update(device).set({ userId: null }).where(inArray(device.id, deviceIds));
  }

  // 5. Delete the user row last.
  await db.delete(user).where(eq(user.id, userId));

  return {
    status: 'deleted',
    userId,
    assetsScheduled: assetIds.length,
    linksRevoked,
    devicesUnlinked: deviceIds.length,
  };
}
