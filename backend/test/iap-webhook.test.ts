import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  installDrizzleFake,
  resetStore,
  resetKv,
  store,
  TEST_ENV,
  ctx,
} from './support';

installDrizzleFake();

// `notificationType` is embedded in the signedPayload string so the fake
// verifier can route to the right canned shape. `signedPayload` values are
// not real JWS — they're 20+ char test fixtures decoded by the mock.
interface NotificationFixtureOpts {
  type: string;
  subtype?: string;
  notificationUUID?: string;
  productId?: string;
  expiresDate?: number | null;
  autoRenewStatus?: boolean;
  bundleId?: string;
  environment?: 'Production' | 'Sandbox';
}

function notifPayload(opts: NotificationFixtureOpts): string {
  return `NOTIF_FIXTURE_${JSON.stringify(opts)}`;
}

vi.mock('~/lib/appStoreServerApi', async () => {
  const actual = await vi.importActual<typeof import('~/lib/appStoreServerApi')>(
    '~/lib/appStoreServerApi',
  );
  return {
    ...actual,
    createAppStoreServerApi: () => ({
      verifyTransactionJWS: async (jws: string) => {
        if (jws === 'BAD_TX') throw new actual.InvalidJwsError('signature_verify_failed');
        const prefix = 'NOTIF_FIXTURE_';
        if (jws.startsWith(prefix)) {
          const opts = JSON.parse(jws.slice(prefix.length)) as NotificationFixtureOpts;
          return {
            transactionId: `TX-${opts.type}`,
            originalTransactionId: 'OTX-WEBHOOK',
            productId: opts.productId ?? 'red.fastsha.pro.monthly',
            purchaseDate: new Date('2026-04-01T00:00:00Z'),
            expiresDate:
              opts.expiresDate === null
                ? null
                : new Date(opts.expiresDate ?? Date.parse('2026-05-15T00:00:00Z')),
            environment: opts.environment ?? 'Production',
            bundleId: opts.bundleId ?? 'red.fastsha.FastShared',
            raw: {},
          };
        }
        throw new actual.InvalidJwsError('unknown_fixture');
      },
      verifyRenewalInfoJWS: async (jws: string) => {
        const prefix = 'NOTIF_FIXTURE_';
        if (jws.startsWith(prefix)) {
          const opts = JSON.parse(jws.slice(prefix.length)) as NotificationFixtureOpts;
          return {
            originalTransactionId: 'OTX-WEBHOOK',
            autoRenewStatus: opts.autoRenewStatus ?? true,
            autoRenewProductId: opts.productId ?? null,
            expirationIntent: null,
            environment: opts.environment ?? 'Production',
            raw: {},
          };
        }
        throw new actual.InvalidJwsError('unknown_fixture');
      },
      verifyNotificationJWS: async (signedPayload: string) => {
        if (signedPayload === 'BAD_SIGNATURE_FIXTURE_00') {
          throw new actual.InvalidJwsError('signature_verify_failed');
        }
        const prefix = 'NOTIF_FIXTURE_';
        if (!signedPayload.startsWith(prefix)) {
          throw new actual.InvalidJwsError('unknown_fixture');
        }
        const opts = JSON.parse(signedPayload.slice(prefix.length)) as NotificationFixtureOpts;
        return {
          notificationType: opts.type,
          subtype: opts.subtype ?? null,
          notificationUUID: opts.notificationUUID ?? 'uuid-default',
          signedDate: new Date(),
          version: '2.0',
          data: {
            bundleId: opts.bundleId ?? 'red.fastsha.FastShared',
            environment: opts.environment ?? 'Production',
            signedTransactionInfo: signedPayload, // reuse same shape
            signedRenewalInfo: signedPayload,
            status: null,
            appAppleId: null,
          },
          raw: {},
        };
      },
      getSubscriptionStatus: async () => ({
        status: 0,
        tier: 'monthly' as const,
        expiresDate: null,
        autoRenewStatus: true,
        latestTransactionId: 'TX',
        originalTransactionId: 'OTX-WEBHOOK',
        environment: 'Production' as const,
        raw: {},
      }),
    }),
  };
});

import worker from '~/index';

async function post(
  path: string,
  bodyObj: unknown,
  headers: Record<string, string> = {},
): Promise<Response> {
  return worker.fetch(
    new Request(`https://api.fastsha.red${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: JSON.stringify(bodyObj),
    }),
    TEST_ENV,
    ctx,
  );
}

function seedSubscription(overrides: Partial<(typeof store.subscriptions)[number]> = {}) {
  const deviceId = crypto.randomUUID();
  store.devices.push({
    id: deviceId,
    tokenHash: 'th',
    platform: 'ios',
    appVersion: '0.1.0',
    userId: null,
  });
  store.subscriptions.push({
    id: crypto.randomUUID(),
    deviceId,
    appleOriginalTransactionId: 'OTX-WEBHOOK',
    tier: 'monthly',
    status: 'active',
    expiresAt: new Date('2026-05-01T00:00:00Z'),
    autoRenewStatus: true,
    latestTransactionId: 'TX-INITIAL',
    rawNotificationPayload: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  });
}

describe('POST /v1/iap/webhook', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('DID_RENEW → sub.status becomes active with bumped expiresAt', async () => {
    seedSubscription({ status: 'in_grace' });
    const payload = notifPayload({
      type: 'DID_RENEW',
      notificationUUID: 'uuid-renew',
      expiresDate: Date.parse('2026-06-01T00:00:00Z'),
    });
    const res = await post('/v1/iap/webhook', { signedPayload: payload });
    expect(res.status).toBe(200);
    const row = store.subscriptions[0]!;
    expect(row.status).toBe('active');
    expect(row.expiresAt?.toISOString()).toBe(new Date('2026-06-01T00:00:00Z').toISOString());
  });

  it('EXPIRED → sub.status becomes expired', async () => {
    seedSubscription();
    const payload = notifPayload({ type: 'EXPIRED', notificationUUID: 'uuid-expired' });
    const res = await post('/v1/iap/webhook', { signedPayload: payload });
    expect(res.status).toBe(200);
    expect(store.subscriptions[0]!.status).toBe('expired');
  });

  it('REFUND → sub.status becomes refunded', async () => {
    seedSubscription();
    const payload = notifPayload({ type: 'REFUND', notificationUUID: 'uuid-refund' });
    const res = await post('/v1/iap/webhook', { signedPayload: payload });
    expect(res.status).toBe(200);
    expect(store.subscriptions[0]!.status).toBe('refunded');
  });

  it('GRACE_PERIOD_EXPIRED → sub.status becomes expired', async () => {
    seedSubscription({ status: 'in_grace' });
    const payload = notifPayload({
      type: 'GRACE_PERIOD_EXPIRED',
      notificationUUID: 'uuid-gpe',
    });
    const res = await post('/v1/iap/webhook', { signedPayload: payload });
    expect(res.status).toBe(200);
    expect(store.subscriptions[0]!.status).toBe('expired');
  });

  it('DID_CHANGE_RENEWAL_STATUS → status unchanged, autoRenewStatus flips', async () => {
    seedSubscription({ status: 'active', autoRenewStatus: true });
    const payload = notifPayload({
      type: 'DID_CHANGE_RENEWAL_STATUS',
      notificationUUID: 'uuid-dcrs',
      autoRenewStatus: false,
    });
    const res = await post('/v1/iap/webhook', { signedPayload: payload });
    expect(res.status).toBe(200);
    expect(store.subscriptions[0]!.status).toBe('active');
    expect(store.subscriptions[0]!.autoRenewStatus).toBe(false);
  });

  it('DID_FAIL_TO_RENEW + subtype=GRACE_PERIOD → in_grace', async () => {
    seedSubscription();
    const payload = notifPayload({
      type: 'DID_FAIL_TO_RENEW',
      subtype: 'GRACE_PERIOD',
      notificationUUID: 'uuid-gp',
    });
    const res = await post('/v1/iap/webhook', { signedPayload: payload });
    expect(res.status).toBe(200);
    expect(store.subscriptions[0]!.status).toBe('in_grace');
  });

  it('DID_FAIL_TO_RENEW without subtype → in_billing_retry', async () => {
    seedSubscription();
    const payload = notifPayload({
      type: 'DID_FAIL_TO_RENEW',
      notificationUUID: 'uuid-br',
    });
    const res = await post('/v1/iap/webhook', { signedPayload: payload });
    expect(res.status).toBe(200);
    expect(store.subscriptions[0]!.status).toBe('in_billing_retry');
  });

  it('invalid JWS → 401', async () => {
    const res = await post('/v1/iap/webhook', { signedPayload: 'BAD_SIGNATURE_FIXTURE_00' });
    expect(res.status).toBe(401);
  });

  it('wrong bundleId → 200 no-op (ignored)', async () => {
    seedSubscription();
    const payload = notifPayload({
      type: 'DID_RENEW',
      notificationUUID: 'uuid-wrongbundle',
      bundleId: 'com.attacker.app',
    });
    const res = await post('/v1/iap/webhook', { signedPayload: payload });
    expect(res.status).toBe(200);
    // Unchanged.
    expect(store.subscriptions[0]!.status).toBe('active');
  });

  it('replay of same notificationUUID → 200, no second DB write, KV key present', async () => {
    seedSubscription();
    const payload = notifPayload({
      type: 'EXPIRED',
      notificationUUID: 'uuid-replay',
    });
    const first = await post('/v1/iap/webhook', { signedPayload: payload });
    expect(first.status).toBe(200);
    expect(store.subscriptions[0]!.status).toBe('expired');

    // Manually flip back to observe the no-op on replay.
    store.subscriptions[0]!.status = 'active';
    const second = await post('/v1/iap/webhook', { signedPayload: payload });
    expect(second.status).toBe(200);
    // Replay should not have rewritten anything — still 'active'.
    expect(store.subscriptions[0]!.status).toBe('active');

    const kvMap = (TEST_ENV.RATE_LIMIT as unknown as { __map: Map<string, string> }).__map;
    expect(kvMap.has('iap:notif:uuid-replay')).toBe(true);
  });
});
