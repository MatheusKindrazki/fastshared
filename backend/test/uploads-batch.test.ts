import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  installDrizzleFake,
  resetStore,
  resetKv,
  store,
  TEST_ENV,
  ctx,
  seedDevice,
} from './support';
import { hmacSha256Hex } from '~/lib/hash';

installDrizzleFake();

// Keep the Free gate explicit in this suite even if caps are retuned later.
vi.mock('~/lib/tierCaps', async () => {
  const actual = await vi.importActual<typeof import('~/lib/tierCaps')>('~/lib/tierCaps');
  return {
    ...actual,
    FREE_CAPS: {
      uploadsPerDay: 3,
      maxFileSizeMB: 100,
      maxRetentionHours: 24,
      allowsCloudSync: false,
    },
  };
});

async function freeTierKvKey(deviceId: string): Promise<string> {
  const utcDate = new Date().toISOString().slice(0, 10);
  const digest = await hmacSha256Hex(TEST_ENV.DEVICE_TOKEN_PEPPER, deviceId);
  return `ft:${digest.slice(0, 32)}:${utcDate}`;
}

// R2 presigns: replicate the lightweight stubs used by uploads.test.ts /
// rateLimitFreeTier.test.ts so the batch route can complete without touching
// the real AWS SDK. headObject is dynamic — the M2 /complete tests need to
// fake an "object exists in R2 with size N" reply per call. The mock var is
// hoisted via vi.hoisted so the factory closure can capture it.
const r2Mocks = vi.hoisted(() => ({
  headObject: vi.fn(
    async (_args: {
      env: unknown;
      key: string;
    }): Promise<{ sizeBytes: number; contentType?: string; etag?: string } | null> => null,
  ),
}));
vi.mock('~/services/r2', async () => {
  const actual = await vi.importActual<typeof import('~/services/r2')>('~/services/r2');
  return {
    ...actual,
    presignPut: async ({
      key,
      contentType,
      sizeBytes,
    }: {
      key: string;
      contentType: string;
      sizeBytes: number;
    }) => ({
      url: `https://r2.test/${key}?sig=x`,
      method: 'PUT' as const,
      headers: { 'content-type': contentType, 'content-length': String(sizeBytes) },
      expiresAt: new Date(Date.now() + 900_000).toISOString(),
    }),
    presignGet: async ({ key }: { key: string }) => `https://r2.test/${key}?get=x`,
    headObject: (args: { env: unknown; key: string }) => r2Mocks.headObject(args),
    deleteObject: async () => undefined,
    createMultipartUpload: async () => ({ uploadId: 'mpu-test-id' }),
    presignPart: async (_env: unknown, key: string, uploadId: string, partNumber: number) =>
      `https://r2.test/${key}?uploadId=${uploadId}&partNumber=${partNumber}&sig=x`,
    completeMultipartUpload: async () => undefined,
    abortMultipartUpload: async () => undefined,
  };
});

import worker from '~/index';

async function post(path: string, body: unknown, headers: Record<string, string> = {}) {
  return worker.fetch(
    new Request(`https://api.fastsha.red${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: JSON.stringify(body),
    }),
    TEST_ENV,
    ctx,
  );
}

function makeItem(
  overrides: Partial<{
    clientJobId: string;
    contentType: string;
    sizeBytes: number;
    sha256: string;
    originalFilename: string;
  }> = {},
) {
  return {
    clientJobId: overrides.clientJobId ?? crypto.randomUUID(),
    contentType: overrides.contentType ?? 'image/jpeg',
    sizeBytes: overrides.sizeBytes ?? 1024,
    ...(overrides.sha256 ? { sha256: overrides.sha256 } : {}),
    ...(overrides.originalFilename ? { originalFilename: overrides.originalFilename } : {}),
  };
}

function seedActiveSub(deviceId: string) {
  store.subscriptions.push({
    id: crypto.randomUUID(),
    deviceId,
    appleOriginalTransactionId: 'OTX-PRO-BATCH',
    tier: 'monthly',
    status: 'active',
    expiresAt: new Date(Date.now() + 30 * 86_400 * 1000),
    autoRenewStatus: true,
    latestTransactionId: 'TX',
    verificationStatus: 'verified',
    verificationGraceUntil: null,
    rawNotificationPayload: null,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
}

describe('POST /uploads/batch', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    delete TEST_ENV.PRO_FOR_ALL_USERS;
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('happy path: 3 valid items mints one bundle + 3 jobs', async () => {
    const { token } = await seedDevice();
    const items = [makeItem(), makeItem(), makeItem()];

    const res = await post(
      '/v1/uploads/batch',
      { retentionPolicy: 'oneDay', visibility: 'signed', items },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);

    const body = (await res.json()) as {
      bundleToken: string;
      bundleShortUrl: string;
      itemCount: number;
      retentionPolicy: string;
      items: Array<{
        clientJobId: string;
        uploadId: string;
        upload: { mode: string; url?: string };
      }>;
    };

    expect(body.itemCount).toBe(3);
    expect(body.items).toHaveLength(3);
    expect(body.bundleShortUrl).toBe(`https://fastsha.red/b/${body.bundleToken}`);
    expect(body.retentionPolicy).toBe('oneDay');

    for (let i = 0; i < items.length; i++) {
      const responseItem = body.items[i]!;
      expect(responseItem.clientJobId).toBe(items[i]!.clientJobId);
      expect(responseItem.uploadId).toBeTruthy();
      expect(responseItem.upload.mode).toBe('single');
      expect(responseItem.upload.url).toContain('https://r2.test/');
    }

    // DB: exactly one bundle share_link in pending state, no assetId yet.
    expect(store.shareLinks).toHaveLength(1);
    const link = store.shareLinks[0]!;
    expect(link.token).toBe(body.bundleToken);
    expect(link.isBundle).toBe(true);
    expect(link.assetId).toBeNull();
    expect(link.bundleAssetCount).toBe(3);
    expect(link.linkStatus).toBe('pending');

    // DB: one upload_job per item, all carrying the bundleToken.
    expect(store.uploadJobs).toHaveLength(3);
    for (const item of items) {
      const job = store.uploadJobs.find((j) => j.clientJobId === item.clientJobId);
      expect(job).toBeDefined();
      expect(job!.pendingShareLinkToken).toBe(body.bundleToken);
      expect(job!.status).toBe('presigned');
    }
  });

  it('free cap rejection: KV pre-seeded at 2, batch of 2 trips daily cap and rolls back', async () => {
    const { deviceId, token } = await seedDevice();
    const kvKey = await freeTierKvKey(deviceId);
    // 2 already used + 2 in this batch = 4 > FREE_CAPS.uploadsPerDay (3).
    await TEST_ENV.RATE_LIMIT.put(kvKey, '2');

    const res = await post(
      '/v1/uploads/batch',
      {
        retentionPolicy: 'oneDay',
        visibility: 'signed',
        items: [makeItem(), makeItem()],
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(429);

    const body = (await res.json()) as {
      code?: string;
      limit?: number;
      used?: number;
      requested?: number;
    };
    expect(body.code).toBe('free_tier_daily_exceeded');
    expect(body.limit).toBe(3);
    expect(body.used).toBe(2);
    expect(body.requested).toBe(2);

    // Rollback: nothing was written, and the KV counter was NOT incremented.
    expect(store.shareLinks).toHaveLength(0);
    expect(store.uploadJobs).toHaveLength(0);
    const kvMap = (TEST_ENV.RATE_LIMIT as unknown as { __map: Map<string, string> }).__map;
    expect(kvMap.get(kvKey)).toBe('2');
  });

  it('PRO_FOR_ALL_USERS=true bypasses batch Free daily cap', async () => {
    TEST_ENV.PRO_FOR_ALL_USERS = 'true';
    const { deviceId, token } = await seedDevice();
    const kvKey = await freeTierKvKey(deviceId);
    await TEST_ENV.RATE_LIMIT.put(kvKey, '2');

    const items = [makeItem(), makeItem()];
    const res = await post(
      '/v1/uploads/batch',
      {
        retentionPolicy: 'oneMonth',
        visibility: 'signed',
        items,
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);

    const body = (await res.json()) as { retentionPolicy: string; items: unknown[] };
    expect(body.retentionPolicy).toBe('oneMonth');
    expect(body.items).toHaveLength(2);

    const kvMap = (TEST_ENV.RATE_LIMIT as unknown as { __map: Map<string, string> }).__map;
    expect(kvMap.get(kvKey)).toBe('2');
  });

  it('items.length < 2 → 400 zod validation error', async () => {
    const { token } = await seedDevice();
    const res = await post(
      '/v1/uploads/batch',
      {
        retentionPolicy: 'oneDay',
        visibility: 'signed',
        items: [makeItem()],
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(400);
    expect(store.shareLinks).toHaveLength(0);
    expect(store.uploadJobs).toHaveLength(0);
  });

  it('disallowed content-type on one item → 415, no DB writes', async () => {
    const { token } = await seedDevice();
    const res = await post(
      '/v1/uploads/batch',
      {
        retentionPolicy: 'oneDay',
        visibility: 'signed',
        items: [
          makeItem({ contentType: 'image/jpeg', sizeBytes: 1024 }),
          makeItem({ contentType: 'application/x-msdownload', sizeBytes: 1024 }),
        ],
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(415);
    expect(store.shareLinks).toHaveLength(0);
    expect(store.uploadJobs).toHaveLength(0);
  });

  it('per-item size limit exceeded → 413, no DB writes', async () => {
    const { token } = await seedDevice();
    const res = await post(
      '/v1/uploads/batch',
      {
        retentionPolicy: 'oneDay',
        visibility: 'signed',
        items: [
          makeItem({ contentType: 'image/jpeg', sizeBytes: 999_999_999 }),
          makeItem({ contentType: 'image/jpeg', sizeBytes: 1024 }),
        ],
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(413);
    expect(store.shareLinks).toHaveLength(0);
    expect(store.uploadJobs).toHaveLength(0);
  });

  it('Pro user bypasses the daily cap', async () => {
    const { deviceId, token } = await seedDevice();
    seedActiveSub(deviceId);

    const items = Array.from({ length: 10 }, () => makeItem());
    const res = await post(
      '/v1/uploads/batch',
      { retentionPolicy: 'oneDay', visibility: 'signed', items },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);

    const body = (await res.json()) as { itemCount: number };
    expect(body.itemCount).toBe(10);
    expect(store.uploadJobs).toHaveLength(10);

    // Pro path doesn't touch the Free-tier KV counter.
    const kvMap = (TEST_ENV.RATE_LIMIT as unknown as { __map: Map<string, string> }).__map;
    expect(kvMap.get(await freeTierKvKey(deviceId))).toBeUndefined();
  });

  it('two consecutive batches mint distinct bundle tokens', async () => {
    const { token } = await seedDevice();

    const first = await post(
      '/v1/uploads/batch',
      {
        retentionPolicy: 'oneDay',
        visibility: 'signed',
        items: [makeItem(), makeItem()],
      },
      { authorization: `Bearer ${token}` },
    );
    // Reset KV between batches so we don't trip the Free cap on the second call.
    resetKv();
    const second = await post(
      '/v1/uploads/batch',
      {
        retentionPolicy: 'oneDay',
        visibility: 'signed',
        items: [makeItem(), makeItem()],
      },
      { authorization: `Bearer ${token}` },
    );

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);

    const a = (await first.json()) as { bundleToken: string };
    const b = (await second.json()) as { bundleToken: string };
    expect(a.bundleToken).not.toBe(b.bundleToken);
  });
});

// ---------------------------------------------------------------------------
// Milestone 2 — POST /uploads/:uploadId/complete on bundle items.
// /complete on a job whose pendingShareLinkToken points at an isBundle=true
// share_link should append a bundle_asset junction row, keep linkStatus
// 'pending' until the count matches bundleAssetCount, then flip to 'active'.
// ---------------------------------------------------------------------------

interface SeededBundle {
  bundleToken: string;
  bundleShareLinkId: string;
  jobIds: string[];
}

function seedPendingBundle(args: {
  deviceId: string;
  count: number;
  token?: string;
  retentionPolicy?: string;
}): SeededBundle {
  const bundleToken = args.token ?? `bundleTok${Math.random().toString(36).slice(2, 10)}`;
  const bundleShareLinkId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + 86_400_000);
  const deleteAfter = new Date(Date.now() + 2 * 86_400_000);
  store.shareLinks.push({
    id: bundleShareLinkId,
    token: bundleToken,
    assetId: null,
    visibility: 'signed',
    expiresAt,
    hits: 0,
    linkStatus: 'pending',
    retentionPolicy: args.retentionPolicy ?? 'oneDay',
    revokedAt: null,
    lastAccessedAt: null,
    accessCount: 0,
    maxAccessCount: null,
    createdAt: new Date(),
    isBundle: true,
    bundleAssetCount: args.count,
  });
  const jobIds: string[] = [];
  for (let i = 0; i < args.count; i++) {
    const jobId = crypto.randomUUID();
    jobIds.push(jobId);
    store.uploadJobs.push({
      id: jobId,
      deviceId: args.deviceId,
      clientJobId: crypto.randomUUID(),
      assetId: null,
      status: 'presigned',
      retentionPolicy: 'oneDay',
      expiresAt,
      deleteAfter,
      pendingShareLinkToken: bundleToken,
      createdAt: new Date(),
    });
  }
  return { bundleToken, bundleShareLinkId, jobIds };
}

describe('POST /uploads/:uploadId/complete (bundle path, M2)', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    r2Mocks.headObject.mockReset();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('penultimate /complete keeps bundle pending; last one flips it active', async () => {
    const { deviceId, token } = await seedDevice();
    const seeded = seedPendingBundle({ deviceId, count: 2 });

    // Both /complete calls report a real R2 object exists.
    r2Mocks.headObject.mockResolvedValue({
      sizeBytes: 1024,
      contentType: 'image/jpeg',
      etag: 'x',
    });

    const res1 = await post(
      `/v1/uploads/${seeded.jobIds[0]}/complete`,
      {
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        sha256: 'a'.repeat(64),
        originalFilename: 'one.jpg',
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res1.status).toBe(200);

    // Bundle link is still pending after the first complete; one junction row.
    const linkAfter1 = store.shareLinks.find((l) => l.token === seeded.bundleToken)!;
    expect(linkAfter1.linkStatus).toBe('pending');
    expect(store.bundleAssets.length).toBe(1);
    expect(store.bundleAssets[0]!.shareLinkId).toBe(seeded.bundleShareLinkId);
    expect(store.bundleAssets[0]!.displayOrder).toBe(0);

    const res2 = await post(
      `/v1/uploads/${seeded.jobIds[1]}/complete`,
      {
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        sha256: 'b'.repeat(64),
        originalFilename: 'two.jpg',
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res2.status).toBe(200);

    const linkAfter2 = store.shareLinks.find((l) => l.token === seeded.bundleToken)!;
    expect(linkAfter2.linkStatus).toBe('active');
    expect(store.bundleAssets.length).toBe(2);
    const orders = store.bundleAssets
      .filter((b) => b.shareLinkId === seeded.bundleShareLinkId)
      .map((b) => b.displayOrder)
      .sort();
    expect(orders).toEqual([0, 1]);

    // Response carries isBundle + bundle short URL.
    const body2 = (await res2.json()) as {
      shortUrl: string;
      isBundle?: boolean;
      linkStatus: string;
    };
    expect(body2.isBundle).toBe(true);
    expect(body2.linkStatus).toBe('active');
    expect(body2.shortUrl).toBe(`https://fastsha.red/b/${seeded.bundleToken}`);
  });

  it('idempotent /complete on the same uploadId does not duplicate bundle_asset rows', async () => {
    const { deviceId, token } = await seedDevice();
    const seeded = seedPendingBundle({ deviceId, count: 2 });

    r2Mocks.headObject.mockResolvedValue({
      sizeBytes: 1024,
      contentType: 'image/jpeg',
      etag: 'x',
    });

    const body = {
      contentType: 'image/jpeg',
      sizeBytes: 1024,
      sha256: 'c'.repeat(64),
      originalFilename: 'idem.jpg',
    };
    const first = await post(`/v1/uploads/${seeded.jobIds[0]}/complete`, body, {
      authorization: `Bearer ${token}`,
    });
    expect(first.status).toBe(200);
    const second = await post(`/v1/uploads/${seeded.jobIds[0]}/complete`, body, {
      authorization: `Bearer ${token}`,
    });
    expect(second.status).toBe(200);

    // Still exactly one junction row — second call short-circuits.
    expect(store.bundleAssets.length).toBe(1);
    // Only 1 of 2 jobs completed, so the bundle remains pending.
    const link = store.shareLinks.find((l) => l.token === seeded.bundleToken)!;
    expect(link.linkStatus).toBe('pending');
  });

  it('intra-bundle dedup: two jobs with the same sha256 reuse one asset, both link', async () => {
    const { deviceId, token } = await seedDevice();
    const seeded = seedPendingBundle({ deviceId, count: 2 });

    // Pre-populate a live asset that matches the sha256 we'll send. Both
    // /complete calls should dedup onto this existing row, not insert new
    // assets — the unique (owner_device_id, sha256) index would otherwise
    // explode on the second insert.
    const sha = 'd'.repeat(64);
    const existingAssetId = crypto.randomUUID();
    store.assets.push({
      id: existingAssetId,
      ownerDeviceId: deviceId,
      bucket: 'b',
      storageKey: 'uploads/xx/2026/04/19/preexisting.jpg',
      contentType: 'image/jpeg',
      sizeBytes: 1024,
      sha256: sha,
      originalFilename: 'preexisting.jpg',
      status: 'verified',
      createdAt: new Date(),
      verifiedAt: new Date(),
      deletedAt: null,
      deleteAfter: new Date(Date.now() + 2 * 86_400_000),
      deletionStatus: 'pending',
      deletionAttempts: 0,
      deletionLastError: null,
    });

    r2Mocks.headObject.mockResolvedValue({
      sizeBytes: 1024,
      contentType: 'image/jpeg',
      etag: 'x',
    });

    const completeBody = {
      contentType: 'image/jpeg',
      sizeBytes: 1024,
      sha256: sha,
      originalFilename: 'dup.jpg',
    };

    const r1 = await post(`/v1/uploads/${seeded.jobIds[0]}/complete`, completeBody, {
      authorization: `Bearer ${token}`,
    });
    expect(r1.status).toBe(200);
    const r2 = await post(`/v1/uploads/${seeded.jobIds[1]}/complete`, completeBody, {
      authorization: `Bearer ${token}`,
    });
    expect(r2.status).toBe(200);

    // Dedup: still only one asset row in the store.
    expect(store.assets).toHaveLength(1);
    expect(store.assets[0]!.id).toBe(existingAssetId);

    // Junction is keyed by (shareLinkId, uploadJobId), not assetId — two
    // slots dedup'd to the same asset still yield two distinct junction rows
    // with stable displayOrder. UX: user sees both files they dropped.
    const junctions = store.bundleAssets
      .filter((b) => b.shareLinkId === seeded.bundleShareLinkId)
      .sort((a, b) => a.displayOrder - b.displayOrder);
    expect(junctions).toHaveLength(2);
    expect(junctions[0]!.assetId).toBe(existingAssetId);
    expect(junctions[1]!.assetId).toBe(existingAssetId);
    expect(junctions.map((j) => j.displayOrder)).toEqual([0, 1]);
    const link = store.shareLinks.find((l) => l.token === seeded.bundleToken)!;
    expect(link.linkStatus).toBe('active');
  });
});
