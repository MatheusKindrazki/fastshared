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

installDrizzleFake();

// Mock the App Store Server API module so we don't need a real Apple root
// chain / p8 keypair. The route wires our fake back in and we assert on the
// call arguments + resulting DB row.
vi.mock('~/lib/appStoreServerApi', async () => {
  const actual = await vi.importActual<typeof import('~/lib/appStoreServerApi')>(
    '~/lib/appStoreServerApi',
  );
  return {
    ...actual,
    createAppStoreServerApi: () => ({
      verifyTransactionJWS: async (jws: string) => {
        if (jws === 'INVALID_JWS_FIXTURE_TOKEN_00000000') {
          throw new actual.InvalidJwsError('signature_verify_failed');
        }
        if (jws === 'JWS_MONTHLY_PROD_FIXTURE_0001') {
          return {
            transactionId: 'TX-1',
            originalTransactionId: 'OTX-1',
            productId: 'red.fastsha.pro.monthly',
            purchaseDate: new Date('2026-04-01T00:00:00Z'),
            expiresDate: new Date('2026-05-01T00:00:00Z'),
            environment: 'Production' as const,
            bundleId: 'red.fastsha.FastShared',
            raw: {},
          };
        }
        if (jws === 'JWS_LIFETIME_PROD_FIXTURE_0002') {
          return {
            transactionId: 'TX-LT',
            originalTransactionId: 'OTX-LT',
            productId: 'red.fastsha.pro.lifetime',
            purchaseDate: new Date('2026-04-01T00:00:00Z'),
            expiresDate: null,
            environment: 'Production' as const,
            bundleId: 'red.fastsha.FastShared',
            raw: {},
          };
        }
        if (jws === 'JWS_UNKNOWN_PRODUCT_FIXTURE_0003') {
          return {
            transactionId: 'TX-UP',
            originalTransactionId: 'OTX-UP',
            productId: 'red.fastsha.pro.not-a-product',
            purchaseDate: new Date('2026-04-01T00:00:00Z'),
            expiresDate: new Date('2026-05-01T00:00:00Z'),
            environment: 'Production' as const,
            bundleId: 'red.fastsha.FastShared',
            raw: {},
          };
        }
        if (jws === 'JWS_SANDBOX_FIXTURE_0004_00000') {
          return {
            transactionId: 'TX-SB',
            originalTransactionId: 'OTX-SB',
            productId: 'red.fastsha.pro.monthly',
            purchaseDate: new Date('2026-04-01T00:00:00Z'),
            expiresDate: new Date('2026-05-01T00:00:00Z'),
            environment: 'Sandbox' as const,
            bundleId: 'red.fastsha.FastShared',
            raw: {},
          };
        }
        if (jws === 'JWS_MONTHLY_REPEAT_FIXTURE_0005') {
          return {
            transactionId: 'TX-1B',
            originalTransactionId: 'OTX-1',
            productId: 'red.fastsha.pro.monthly',
            purchaseDate: new Date('2026-04-01T00:00:00Z'),
            expiresDate: new Date('2026-06-01T00:00:00Z'),
            environment: 'Production' as const,
            bundleId: 'red.fastsha.FastShared',
            raw: {},
          };
        }
        if (jws === 'JWS_STATUS_FAIL_FIXTURE_0006') {
          return {
            transactionId: 'TX-GRACE',
            originalTransactionId: 'OTX-GRACE',
            productId: 'red.fastsha.pro.monthly',
            purchaseDate: new Date('2026-04-01T00:00:00Z'),
            expiresDate: new Date(Date.now() + 7 * 86_400 * 1000),
            environment: 'Production' as const,
            bundleId: 'red.fastsha.FastShared',
            raw: {},
          };
        }
        throw new actual.InvalidJwsError('unknown_fixture');
      },
      verifyRenewalInfoJWS: async () => {
        throw new Error('not used in verify tests');
      },
      verifyNotificationJWS: async () => {
        throw new Error('not used in verify tests');
      },
      getSubscriptionStatus: async (originalTransactionId: string) => {
        if (originalTransactionId === 'OTX-GRACE') {
          throw new actual.AppStoreApiError('network_failure');
        }
        return {
          status: 0,
          tier: 'monthly' as const,
          expiresDate: new Date('2026-05-01T00:00:00Z'),
          autoRenewStatus: true,
          latestTransactionId: 'TX-1',
          originalTransactionId: 'OTX-1',
          environment: 'Production' as const,
          raw: {},
        };
      },
    }),
  };
});

import worker from '~/index';

async function post(
  path: string,
  body: unknown,
  headers: Record<string, string> = {},
): Promise<Response> {
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

describe('POST /v1/iap/verify', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('rejects requests without a bearer token (401)', async () => {
    const res = await post('/v1/iap/verify', { jwsRepresentation: 'JWS_MONTHLY_PROD_FIXTURE_0001' });
    expect(res.status).toBe(401);
  });

  it('rejects invalid JWS structure (422 invalid_receipt)', async () => {
    const { token } = await seedDevice();
    const res = await post(
      '/v1/iap/verify',
      { jwsRepresentation: 'INVALID_JWS_FIXTURE_TOKEN_00000000' },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(422);
    const body = (await res.json()) as { code?: string };
    expect(body.code).toBe('invalid_receipt');
  });

  it('accepts a valid monthly JWS, upserts a row, returns tier=monthly', async () => {
    const { deviceId, token } = await seedDevice();
    const res = await post(
      '/v1/iap/verify',
      { jwsRepresentation: 'JWS_MONTHLY_PROD_FIXTURE_0001' },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      isPro: boolean;
      tier: string;
      expiresAt: string | null;
      caps: { maxFileSizeBytes: number };
      subscription: { status: string; autoRenewStatus: boolean; verificationStatus: string } | null;
    };
    expect(body.isPro).toBe(true);
    expect(body.tier).toBe('monthly');
    expect(body.subscription?.status).toBe('active');
    expect(body.subscription?.verificationStatus).toBe('verified');
    expect(body.expiresAt).not.toBeNull();
    expect(body.caps.maxFileSizeBytes).toBe(2 * 1024 * 1024 * 1024);

    expect(store.subscriptions.length).toBe(1);
    const row = store.subscriptions[0]!;
    expect(row.deviceId).toBe(deviceId);
    expect(row.appleOriginalTransactionId).toBe('OTX-1');
    expect(row.tier).toBe('monthly');
    expect(row.status).toBe('active');
    expect(row.verificationStatus).toBe('verified');
  });

  it('lifetime JWS returns tier=lifetime with expiresAt=null', async () => {
    const { token } = await seedDevice();
    const res = await post(
      '/v1/iap/verify',
      { jwsRepresentation: 'JWS_LIFETIME_PROD_FIXTURE_0002' },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { tier: string; expiresAt: string | null };
    expect(body.tier).toBe('lifetime');
    expect(body.expiresAt).toBeNull();
  });

  it('unknown product ID returns 422 unknown_product', async () => {
    const { token } = await seedDevice();
    const res = await post(
      '/v1/iap/verify',
      { jwsRepresentation: 'JWS_UNKNOWN_PRODUCT_FIXTURE_0003' },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(422);
    const body = (await res.json()) as { code?: string };
    expect(body.code).toBe('unknown_product');
  });

  it('sandbox receipt in production returns 422 invalid_receipt', async () => {
    const { token } = await seedDevice();
    const prodEnv = { ...TEST_ENV, APP_ENV: 'production' };
    const res = await worker.fetch(
      new Request('https://api.fastsha.red/v1/iap/verify', {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
        body: JSON.stringify({ jwsRepresentation: 'JWS_SANDBOX_FIXTURE_0004_00000' }),
      }),
      prodEnv,
      ctx,
    );
    expect(res.status).toBe(422);
  });

  it('repeating /verify for the same originalTransactionId upserts (no duplicate row)', async () => {
    const { token } = await seedDevice();
    const first = await post(
      '/v1/iap/verify',
      { jwsRepresentation: 'JWS_MONTHLY_PROD_FIXTURE_0001' },
      { authorization: `Bearer ${token}` },
    );
    expect(first.status).toBe(200);
    const second = await post(
      '/v1/iap/verify',
      { jwsRepresentation: 'JWS_MONTHLY_REPEAT_FIXTURE_0005' },
      { authorization: `Bearer ${token}` },
    );
    expect(second.status).toBe(200);
    expect(store.subscriptions.length).toBe(1);
    // Upsert keyed on originalTransactionId — same OTX, one row.
    expect(store.subscriptions[0]!.appleOriginalTransactionId).toBe('OTX-1');
  });

  it('accepts legacy signedTransaction field during client rollout', async () => {
    const { token } = await seedDevice();
    const res = await post(
      '/v1/iap/verify',
      { signedTransaction: 'JWS_MONTHLY_PROD_FIXTURE_0001' },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { isPro: boolean; tier: string };
    expect(body.isPro).toBe(true);
    expect(body.tier).toBe('monthly');
  });

  it('App Store Server API failure grants only a 24h verification grace', async () => {
    const { token } = await seedDevice();
    const before = Date.now();
    const res = await post(
      '/v1/iap/verify',
      { jwsRepresentation: 'JWS_STATUS_FAIL_FIXTURE_0006' },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      isPro: boolean;
      subscription: { verificationStatus: string; verificationGraceUntil: string | null } | null;
    };
    expect(body.isPro).toBe(true);
    expect(body.subscription?.verificationStatus).toBe('grace');
    expect(body.subscription?.verificationGraceUntil).not.toBeNull();
    const graceUntil = Date.parse(body.subscription!.verificationGraceUntil!);
    expect(graceUntil).toBeGreaterThanOrEqual(before + 24 * 60 * 60 * 1000 - 5_000);
    expect(graceUntil).toBeLessThanOrEqual(before + 24 * 60 * 60 * 1000 + 5_000);
    expect(store.subscriptions[0]!.verificationStatus).toBe('grace');
  });
});
