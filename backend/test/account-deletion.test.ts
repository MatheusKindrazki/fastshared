// Account deletion — App Store Guideline 5.1.1(v).
//
// The deletion of the `user` row and the SET-NULL fan-out onto `device.user_id`
// is a real Postgres FK behaviour the in-memory drizzle fake does not model, so
// the service is exercised directly against the fake store and we assert on the
// store + the service's return value. A thin HTTP test covers the 400
// not_linked path through the real route + middleware stack.

import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  installDrizzleFake,
  resetStore,
  resetKv,
  store,
  TEST_ENV,
  ctx,
  seedDevice,
  type AssetRow,
} from './support';

installDrizzleFake();

import worker from '~/index';
import { deleteAccountForDevice } from '~/services/accountDeletion';
import { createDb } from '~/db/client';

const db = createDb(TEST_ENV.DATABASE_URL);

function seedUser(id: string): void {
  store.users.push({
    id,
    appleUserId: `apple.${id}`,
    email: `${id}@example.com`,
    fullName: 'Test User',
    createdAt: new Date(),
    updatedAt: new Date(),
  });
}

function seedAsset(overrides: Partial<AssetRow> & { id: string; ownerDeviceId: string }): void {
  store.assets.push({
    ownerUserId: null,
    bucket: 'b',
    storageKey: `uploads/${overrides.id}.bin`,
    contentType: 'application/octet-stream',
    sizeBytes: 16,
    sha256: null,
    originalFilename: 'f.bin',
    status: 'verified',
    createdAt: new Date(),
    verifiedAt: new Date(),
    deletedAt: null,
    deleteAfter: new Date(Date.now() + 86_400_000),
    deletionStatus: 'pending',
    deletionAttempts: 0,
    deletionLastError: null,
    ...overrides,
  });
}

function seedActiveLink(token: string, assetId: string): void {
  store.shareLinks.push({
    id: crypto.randomUUID(),
    token,
    assetId,
    visibility: 'signed',
    expiresAt: new Date(Date.now() + 3_600_000),
    hits: 0,
    linkStatus: 'active',
    retentionPolicy: 'oneDay',
    revokedAt: null,
    lastAccessedAt: null,
    accessCount: 0,
    maxAccessCount: null,
    createdAt: new Date(),
  });
}

describe('deleteAccountForDevice', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('hard-deletes a linked account: removes user, unlinks devices, revokes links, schedules deletions', async () => {
    const userId = crypto.randomUUID();
    seedUser(userId);

    // Two devices on the same account, plus a subscription on the first.
    const deviceA = crypto.randomUUID();
    const deviceB = crypto.randomUUID();
    store.devices.push({
      id: deviceA,
      tokenHash: 'hA',
      platform: 'ios',
      appVersion: '1',
      userId,
    });
    store.devices.push({
      id: deviceB,
      tokenHash: 'hB',
      platform: 'macos',
      appVersion: '1',
      userId,
    });
    store.subscriptions.push({
      id: crypto.randomUUID(),
      deviceId: deviceA,
      appleOriginalTransactionId: 'otx-1',
      tier: 'monthly',
      status: 'active',
      expiresAt: new Date(Date.now() + 86_400_000),
      autoRenewStatus: true,
      latestTransactionId: 'ltx-1',
      verificationStatus: 'verified',
      verificationGraceUntil: null,
      rawNotificationPayload: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    // assetUser: owned via ownerUserId. assetDevice: owned only via a device.
    const assetUser = crypto.randomUUID();
    const assetDevice = crypto.randomUUID();
    seedAsset({ id: assetUser, ownerDeviceId: deviceA, ownerUserId: userId });
    seedAsset({ id: assetDevice, ownerDeviceId: deviceB, ownerUserId: null });
    seedActiveLink('linkUserAAAAAAAAAAAAAA', assetUser);
    seedActiveLink('linkDeviceAAAAAAAAAAAA', assetDevice);

    const result = await deleteAccountForDevice(db, deviceA);

    expect(result.status).toBe('deleted');
    if (result.status !== 'deleted') throw new Error('unreachable');
    expect(result.userId).toBe(userId);
    expect(result.devicesUnlinked).toBe(2);
    expect(result.assetsScheduled).toBe(2);
    expect(result.linksRevoked).toBe(2);

    // User row gone.
    expect(store.users.find((u) => u.id === userId)).toBeUndefined();
    // Devices are unlinked explicitly before deleting the user, so this does
    // not depend on the production FK action being ON DELETE SET NULL.
    expect(store.devices.find((d) => d.id === deviceA)?.userId ?? null).toBeNull();
    expect(store.devices.find((d) => d.id === deviceB)?.userId ?? null).toBeNull();
    // Subscription for the account's devices gone.
    expect(store.subscriptions.length).toBe(0);
    // Both assets had their owner_user_id orphaned before the user delete.
    expect(store.assets.find((a) => a.id === assetUser)?.ownerUserId ?? null).toBeNull();
    // Both share links revoked. (revokedAt is set via sql`now()` in prod; the
    // in-memory fake intentionally can't materialize SQL expressions, so we
    // assert on linkStatus — the observable signal the fake models.)
    expect(store.shareLinks.every((l) => l.linkStatus === 'revoked')).toBe(true);
    // Immediate deletion scheduled for every owned asset.
    const scheduled = new Set(store.deletionJobs.map((j) => j.assetId));
    expect(scheduled.has(assetUser)).toBe(true);
    expect(scheduled.has(assetDevice)).toBe(true);
  });

  it('handles large accounts without per-asset scheduling work', async () => {
    const userId = crypto.randomUUID();
    seedUser(userId);
    const deviceId = crypto.randomUUID();
    store.devices.push({
      id: deviceId,
      tokenHash: 'hLarge',
      platform: 'ios',
      appVersion: '1.0.3',
      userId,
    });

    const assetIds: string[] = [];
    for (let i = 0; i < 120; i += 1) {
      const id = crypto.randomUUID();
      assetIds.push(id);
      seedAsset({
        id,
        ownerDeviceId: deviceId,
        ownerUserId: i % 2 === 0 ? userId : null,
      });
      seedActiveLink(`largeLink${i.toString().padStart(3, '0')}AAAAAAAA`, id);
    }

    const result = await deleteAccountForDevice(db, deviceId);

    expect(result.status).toBe('deleted');
    if (result.status !== 'deleted') throw new Error('unreachable');
    expect(result.assetsScheduled).toBe(120);
    expect(result.linksRevoked).toBe(120);
    expect(store.users.find((u) => u.id === userId)).toBeUndefined();
    expect(store.devices.find((d) => d.id === deviceId)?.userId ?? null).toBeNull();
    const scheduled = new Set(store.deletionJobs.map((j) => j.assetId));
    for (const assetId of assetIds) {
      expect(scheduled.has(assetId)).toBe(true);
    }
  });

  it('does not touch a different account', async () => {
    const mine = crypto.randomUUID();
    const theirs = crypto.randomUUID();
    seedUser(mine);
    seedUser(theirs);

    const myDevice = crypto.randomUUID();
    const theirDevice = crypto.randomUUID();
    store.devices.push({
      id: myDevice,
      tokenHash: 'hM',
      platform: 'ios',
      appVersion: '1',
      userId: mine,
    });
    store.devices.push({
      id: theirDevice,
      tokenHash: 'hT',
      platform: 'ios',
      appVersion: '1',
      userId: theirs,
    });

    const myAsset = crypto.randomUUID();
    const theirAsset = crypto.randomUUID();
    seedAsset({ id: myAsset, ownerDeviceId: myDevice, ownerUserId: mine });
    seedAsset({ id: theirAsset, ownerDeviceId: theirDevice, ownerUserId: theirs });
    seedActiveLink('mineLinkAAAAAAAAAAAAAA', myAsset);
    seedActiveLink('theirLinkAAAAAAAAAAAAA', theirAsset);
    store.subscriptions.push({
      id: crypto.randomUUID(),
      deviceId: theirDevice,
      appleOriginalTransactionId: 'otx-theirs',
      tier: 'annual',
      status: 'active',
      expiresAt: null,
      autoRenewStatus: true,
      latestTransactionId: 'ltx-theirs',
      verificationStatus: 'verified',
      verificationGraceUntil: null,
      rawNotificationPayload: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const result = await deleteAccountForDevice(db, myDevice);
    expect(result.status).toBe('deleted');

    // The other account is fully intact.
    expect(store.users.find((u) => u.id === theirs)).toBeDefined();
    expect(store.devices.find((d) => d.id === theirDevice)?.userId).toBe(theirs);
    expect(store.assets.find((a) => a.id === theirAsset)?.ownerUserId).toBe(theirs);
    expect(store.shareLinks.find((l) => l.token === 'theirLinkAAAAAAAAAAAAA')?.linkStatus).toBe(
      'active',
    );
    expect(store.subscriptions.find((s) => s.deviceId === theirDevice)).toBeDefined();
    // And no deletion was scheduled for the other account's asset.
    expect(store.deletionJobs.some((j) => j.assetId === theirAsset)).toBe(false);
  });

  it('is a no-op-safe success when the account has zero assets', async () => {
    const userId = crypto.randomUUID();
    seedUser(userId);
    const deviceId = crypto.randomUUID();
    store.devices.push({
      id: deviceId,
      tokenHash: 'hZ',
      platform: 'ios',
      appVersion: '1',
      userId,
    });

    const result = await deleteAccountForDevice(db, deviceId);
    expect(result.status).toBe('deleted');
    if (result.status !== 'deleted') throw new Error('unreachable');
    expect(result.assetsScheduled).toBe(0);
    expect(result.linksRevoked).toBe(0);
    expect(result.devicesUnlinked).toBe(1);
    expect(store.users.find((u) => u.id === userId)).toBeUndefined();
    expect(store.devices.find((d) => d.id === deviceId)?.userId ?? null).toBeNull();
    expect(store.deletionJobs.length).toBe(0);
  });

  it('returns device_not_found for an unknown device', async () => {
    const result = await deleteAccountForDevice(db, crypto.randomUUID());
    expect(result.status).toBe('device_not_found');
  });

  it('returns not_linked for a guest (unlinked) device', async () => {
    const { deviceId } = await seedDevice();
    const result = await deleteAccountForDevice(db, deviceId);
    expect(result.status).toBe('not_linked');
  });
});

describe('DELETE /v1/account', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  async function del(token: string): Promise<Response> {
    return worker.fetch(
      new Request('https://api.fastsha.red/v1/account', {
        method: 'DELETE',
        headers: { authorization: `Bearer ${token}` },
      }),
      TEST_ENV,
      ctx,
    );
  }

  it('guest device → 400 not_linked', async () => {
    const { token } = await seedDevice();
    const res = await del(token);
    expect(res.status).toBe(400);
    expect(res.headers.get('Content-Type')).toMatch(/application\/problem\+json/);
    const body = (await res.json()) as { code?: string };
    expect(body.code).toBe('not_linked');
  });

  it('missing bearer token → 401', async () => {
    const res = await worker.fetch(
      new Request('https://api.fastsha.red/v1/account', { method: 'DELETE' }),
      TEST_ENV,
      ctx,
    );
    expect(res.status).toBe(401);
  });

  it('linked device → 200 ok with counts', async () => {
    const userId = crypto.randomUUID();
    seedUser(userId);
    const { deviceId, token } = await seedDevice();
    // Link the seeded device to the user.
    const seeded = store.devices.find((d) => d.id === deviceId)!;
    seeded.userId = userId;

    const assetId = crypto.randomUUID();
    seedAsset({ id: assetId, ownerDeviceId: deviceId, ownerUserId: userId });
    seedActiveLink('httpLinkAAAAAAAAAAAAAA', assetId);

    const res = await del(token);
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      ok: boolean;
      assetsScheduled: number;
      linksRevoked: number;
      devicesUnlinked: number;
    };
    expect(body.ok).toBe(true);
    expect(body.assetsScheduled).toBe(1);
    expect(body.linksRevoked).toBe(1);
    expect(body.devicesUnlinked).toBe(1);
    expect(store.users.find((u) => u.id === userId)).toBeUndefined();
    expect(store.devices.find((d) => d.id === deviceId)?.userId ?? null).toBeNull();
  });
});
