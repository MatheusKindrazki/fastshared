import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  installDrizzleFake,
  resetKv,
  resetStore,
  seedDevice,
  store,
  TEST_ENV,
  ctx,
} from './support';
import { hmacSha256Hex } from '~/lib/hash';

installDrizzleFake();
import worker from '~/index';

const userId = '11111111-1111-4111-8111-111111111111';
const secret = 'paddle-test-secret';
let eventNumber = 0;

async function webhook(
  eventType: string,
  data: Record<string, unknown>,
  options: { signature?: string; timestamp?: number; eventId?: string; occurredAt?: string } = {},
) {
  const body = JSON.stringify({
    event_id: options.eventId ?? `evt_${++eventNumber}`,
    event_type: eventType,
    occurred_at: options.occurredAt ?? new Date().toISOString(),
    data,
  });
  const ts = options.timestamp ?? Math.floor(Date.now() / 1000);
  const signature = options.signature ?? (await hmacSha256Hex(secret, `${ts}:${body}`));
  return worker.fetch(
    new Request('https://api.fastsha.red/v1/billing/paddle/webhook', {
      method: 'POST',
      headers: { 'Paddle-Signature': `ts=${ts};h1=${signature}` },
      body,
    }),
    TEST_ENV,
    ctx,
  );
}

function subscriptionData(status: string, id = 'sub_1') {
  return {
    id,
    status,
    customer_id: 'ctm_1',
    custom_data: { userId },
    current_billing_period: { ends_at: new Date(Date.now() + 30 * 86400_000).toISOString() },
  };
}

beforeEach(async () => {
  resetStore();
  resetKv();
  eventNumber = 0;
  TEST_ENV.PADDLE_WEBHOOK_SECRET = secret;
  delete TEST_ENV.PADDLE_API_KEY;
  TEST_ENV.PADDLE_ENV = 'sandbox';
  store.users.push({
    id: userId,
    appleUserId: null,
    email: 'buyer@example.com',
    fullName: null,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  const ownerDevice = await seedDevice();
  store.devices[0]!.userId = userId;
  store.publications.push({
    id: '22222222-2222-4222-8222-222222222222',
    slug: 'pub1234567',
    ownerUserId: userId,
    ownerDeviceId: ownerDevice.deviceId,
    status: 'active',
    createdAt: new Date(),
    updatedAt: new Date(),
    expiresAt: new Date(Date.now() + 7 * 86400_000),
  });
});

describe('Paddle billing', () => {
  it('rejects invalid and expired signatures', async () => {
    expect(
      (
        await webhook('subscription.created', subscriptionData('active'), {
          signature: '0'.repeat(64),
        })
      ).status,
    ).toBe(401);
    expect(
      (
        await webhook('subscription.created', subscriptionData('active'), {
          timestamp: Math.floor(Date.now() / 1000) - 301,
        })
      ).status,
    ).toBe(401);
    expect(store.entitlements).toHaveLength(0);
  });

  it('creates the entitlement once and clears publication expiry', async () => {
    const eventId = 'evt_same';
    expect(
      (await webhook('subscription.created', subscriptionData('active'), { eventId })).status,
    ).toBe(200);
    expect(
      (await webhook('subscription.created', subscriptionData('active'), { eventId })).status,
    ).toBe(200);
    expect(store.billingEvents).toHaveLength(1);
    expect(store.entitlements).toHaveLength(1);
    expect(store.entitlements[0]?.status).toBe('active');
    expect(store.publications[0]?.expiresAt).toBeNull();
  });

  it.each([
    ['subscription.updated', 'past_due', 'past_due'],
    ['subscription.activated', 'active', 'active'],
    ['subscription.past_due', 'active', 'past_due'],
    ['subscription.canceled', 'active', 'canceled'],
  ])('handles %s', async (type, incomingStatus, expectedStatus) => {
    await webhook('subscription.created', subscriptionData('active'));
    const response = await webhook(type, subscriptionData(incomingStatus), {
      occurredAt: new Date(Date.now() + 1000).toISOString(),
    });
    expect(response.status).toBe(200);
    expect(store.entitlements[0]?.status).toBe(expectedStatus);
    if (expectedStatus === 'active') expect(store.publications[0]?.expiresAt).toBeNull();
    else
      expect(store.publications[0]?.expiresAt.getTime() - Date.now()).toBeGreaterThan(
        29 * 86400_000,
      );
  });

  it('uses transaction.completed and ignores older events', async () => {
    await webhook('transaction.completed', {
      id: 'txn_1',
      subscription_id: 'sub_1',
      customer_id: 'ctm_1',
      custom_data: { userId },
    });
    expect(store.entitlements[0]?.status).toBe('active');
    await webhook('subscription.canceled', subscriptionData('canceled'), {
      occurredAt: new Date(Date.now() + 2000).toISOString(),
    });
    await webhook('subscription.updated', subscriptionData('active'), {
      occurredAt: new Date(Date.now() - 1000).toISOString(),
    });
    expect(store.entitlements[0]?.status).toBe('canceled');
  });

  it('keeps publications active when another entitlement remains Pro', async () => {
    store.entitlements.push({
      id: crypto.randomUUID(),
      userId,
      source: 'iap',
      externalId: 'iap_1',
      status: 'active',
      currentPeriodEnd: null,
      paddleCustomerId: null,
      lastEventAt: null,
    });
    await webhook('subscription.created', subscriptionData('active'));
    await webhook('subscription.canceled', subscriptionData('canceled'), {
      occurredAt: new Date(Date.now() + 1000).toISOString(),
    });
    expect(store.publications[0]?.expiresAt).toBeNull();
  });

  it('returns 503 without the portal API key', async () => {
    const token = (await seedDevice()).token;
    const response = await worker.fetch(
      new Request('https://api.fastsha.red/v1/billing/portal', {
        headers: { authorization: `Bearer ${token}` },
      }),
      TEST_ENV,
      ctx,
    );
    expect(response.status).toBe(503);
  });

  it('creates a temporary portal session for the authenticated customer', async () => {
    await webhook('subscription.created', subscriptionData('active'));
    TEST_ENV.PADDLE_API_KEY = 'test-api-key';
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(
        JSON.stringify({
          data: {
            urls: { general: { overview: 'https://sandbox-customer-portal.paddle.com/session' } },
          },
        }),
        { status: 201, headers: { 'content-type': 'application/json' } },
      ),
    );
    const token = (await seedDevice()).token;
    store.devices.at(-1)!.userId = userId;
    const response = await worker.fetch(
      new Request('https://api.fastsha.red/v1/billing/portal', {
        headers: { authorization: `Bearer ${token}` },
      }),
      TEST_ENV,
      ctx,
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      url: 'https://sandbox-customer-portal.paddle.com/session',
    });
    expect(fetchSpy.mock.calls[0]?.[0]).toBe(
      'https://sandbox-api.paddle.com/customers/ctm_1/portal-sessions',
    );
    fetchSpy.mockRestore();
  });

  it('returns only public checkout config', async () => {
    const response = await worker.fetch(
      new Request('https://api.fastsha.red/v1/billing/config'),
      TEST_ENV,
      ctx,
    );
    expect(await response.json()).toEqual({
      clientToken: '',
      environment: 'sandbox',
      priceIds: { monthly: '', annual: '' },
    });
  });
});
