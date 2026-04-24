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

// R2 presigns are not the subject of these tests; mock them out so
// /v1/uploads/ returns a clean success without hitting the AWS SDK.
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
    headObject: async () => null,
    // Tier 2: multipart helpers — stubbed so the Pro 1 GB path doesn't try to
    // reach real R2. Multipart is not the subject here; we only need the route
    // to return 200 so the Free-cap bypass assertion runs.
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

function seedActiveSub(deviceId: string) {
  store.subscriptions.push({
    id: crypto.randomUUID(),
    deviceId,
    appleOriginalTransactionId: 'OTX-PRO',
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

describe('rateLimitFreeTier', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('first Free upload succeeds and increments the daily counter', async () => {
    const { deviceId, token } = await seedDevice();
    const res = await post(
      '/v1/uploads',
      {
        clientJobId: crypto.randomUUID(),
        contentType: 'image/jpeg',
        sizeBytes: 1024,
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);

    const kvMap = (TEST_ENV.RATE_LIMIT as unknown as { __map: Map<string, string> }).__map;
    expect(kvMap.get(await freeTierKvKey(deviceId))).toBe('1');
  });

  it('4th Free upload returns 402 free_tier_daily_exceeded', async () => {
    const { deviceId, token } = await seedDevice();
    // Pre-seed the counter at 3 → next request trips the cap.
    const kvKey = await freeTierKvKey(deviceId);
    await TEST_ENV.RATE_LIMIT.put(kvKey, '3');

    const res = await post(
      '/v1/uploads',
      {
        clientJobId: crypto.randomUUID(),
        contentType: 'image/jpeg',
        sizeBytes: 1024,
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(402);
    const body = (await res.json()) as { code?: string; limit?: number; used?: number };
    expect(body.code).toBe('free_tier_daily_exceeded');
    expect(body.limit).toBe(3);
    expect(body.used).toBe(3);

    // Counter unchanged on the rejection.
    const kvMap = (TEST_ENV.RATE_LIMIT as unknown as { __map: Map<string, string> }).__map;
    expect(kvMap.get(kvKey)).toBe('3');
  });

  it('Free 200MB upload returns 402 free_tier_size_exceeded without incrementing counter', async () => {
    const { deviceId, token } = await seedDevice();
    const res = await post(
      '/v1/uploads',
      {
        clientJobId: crypto.randomUUID(),
        contentType: 'image/jpeg',
        sizeBytes: 200 * 1024 * 1024,
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(402);
    const body = (await res.json()) as { code?: string; limitMB?: number; actualMB?: number };
    expect(body.code).toBe('free_tier_size_exceeded');
    expect(body.limitMB).toBe(100);
    expect(body.actualMB).toBe(200);

    const kvMap = (TEST_ENV.RATE_LIMIT as unknown as { __map: Map<string, string> }).__map;
    expect(kvMap.get(await freeTierKvKey(deviceId))).toBeUndefined();
  });

  it('Free retentionPolicy=oneWeek silently clamps to oneDay', async () => {
    const { token } = await seedDevice();
    const res = await post(
      '/v1/uploads',
      {
        clientJobId: crypto.randomUUID(),
        contentType: 'image/jpeg',
        sizeBytes: 2048,
        retentionPolicy: 'oneWeek',
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      retentionPolicy: string;
      retentionClamped?: boolean;
      clampedTo?: string;
    };
    expect(body.retentionPolicy).toBe('oneDay');
    expect(body.retentionClamped).toBe(true);
    expect(body.clampedTo).toBe('oneDay');

    // The persisted upload_job also reflects the clamp.
    expect(store.uploadJobs[0]!.retentionPolicy).toBe('oneDay');
  });

  it('Pro uploads bypass the daily cap even at 1 GB', async () => {
    const { deviceId, token } = await seedDevice();
    seedActiveSub(deviceId);

    for (let i = 0; i < 5; i++) {
      const res = await post(
        '/v1/uploads',
        {
          clientJobId: crypto.randomUUID(),
          contentType: 'video/mp4',
          sizeBytes: 1 * 1024 * 1024 * 1024,
        },
        { authorization: `Bearer ${token}` },
      );
      expect(res.status).toBe(200);
    }
    const kvMap = (TEST_ENV.RATE_LIMIT as unknown as { __map: Map<string, string> }).__map;
    expect(kvMap.get(await freeTierKvKey(deviceId))).toBeUndefined();
  });

  it('Pro retentionPolicy=oneMonth is NOT clamped', async () => {
    const { deviceId, token } = await seedDevice();
    seedActiveSub(deviceId);
    const res = await post(
      '/v1/uploads',
      {
        clientJobId: crypto.randomUUID(),
        contentType: 'image/jpeg',
        sizeBytes: 2048,
        retentionPolicy: 'oneMonth',
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { retentionPolicy: string; retentionClamped?: boolean };
    expect(body.retentionPolicy).toBe('oneMonth');
    expect(body.retentionClamped).toBeUndefined();
  });
});
