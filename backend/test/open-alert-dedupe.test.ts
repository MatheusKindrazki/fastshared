import { describe, it, expect, beforeAll, beforeEach, afterEach, vi } from 'vitest';
import { exportPKCS8, generateKeyPair } from 'jose';
import { installDrizzleFake, resetStore, resetKv, store, TEST_ENV, ctx } from './support';

installDrizzleFake();

import worker from '~/index';

const BROWSER_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';

let apnsP8 = '';

function kvMap(): Map<string, string> {
  return (TEST_ENV.RATE_LIMIT as unknown as { __map: Map<string, string> }).__map;
}

function dedupeKeys(): string[] {
  return [...kvMap().keys()].filter((key) => key.startsWith('open:'));
}

function rateLimitKeys(): string[] {
  return [...kvMap().keys()].filter((key) => key.startsWith('rl:'));
}

function seedNotifyingLink(): { token: string } {
  const token = 'dedupeTokenAAAAAAAAAA';
  const deviceId = crypto.randomUUID();
  const assetId = crypto.randomUUID();
  store.devices.push({
    id: deviceId,
    tokenHash: 'dedupe-device-hash',
    platform: 'ios',
    appVersion: '1.0.0',
    apnsToken: 'apns-device-token',
    apnsEnvironment: 'production',
    apnsUpdatedAt: new Date(),
    userId: null,
  });
  store.assets.push({
    id: assetId,
    ownerDeviceId: deviceId,
    bucket: 'b',
    storageKey: `uploads/aa/2026/04/19/${assetId}.bin`,
    contentType: 'image/jpeg',
    sizeBytes: 128,
    sha256: null,
    originalFilename: 'photo.jpg',
    status: 'verified',
    createdAt: new Date(),
    verifiedAt: new Date(),
    deletedAt: null,
    deleteAfter: new Date(Date.now() + 86_400_000),
    deletionStatus: 'pending',
    deletionAttempts: 0,
    deletionLastError: null,
  });
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
    notifyOnOpen: true,
    maxAccessCount: null,
    createdAt: new Date(),
  });
  return { token };
}

async function postOpened(token: string, visitor: string): Promise<Response> {
  return worker.fetch(
    new Request(`https://fastsha.red/s/${token}/opened`, {
      method: 'POST',
      headers: {
        'user-agent': BROWSER_UA,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ visitor }),
      redirect: 'manual',
    }),
    TEST_ENV,
    ctx,
  );
}

describe('open alert dedupe', () => {
  beforeAll(async () => {
    const { privateKey } = await generateKeyPair('ES256', { extractable: true });
    apnsP8 = btoa(await exportPKCS8(privateKey));
  });

  beforeEach(() => {
    resetStore();
    resetKv();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    TEST_ENV.APNS_KEY_ID = 'TESTKEYID1';
    TEST_ENV.APNS_TEAM_ID = 'TEAMID1234';
    TEST_ENV.APNS_P8_KEY_BASE64 = apnsP8;
    TEST_ENV.APNS_TOPIC = 'red.fastsha.FastShared';
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    delete TEST_ENV.APNS_KEY_ID;
    delete TEST_ENV.APNS_TEAM_ID;
    delete TEST_ENV.APNS_P8_KEY_BASE64;
    delete TEST_ENV.APNS_TOPIC;
  });

  it('drops the visitor key when APNs returns 503 and keeps it after a successful send', async () => {
    const { token } = seedNotifyingLink();
    const failing = vi.fn(async (input: RequestInfo | URL) => {
      void input;
      return new Response('unavailable', { status: 503 });
    });
    vi.stubGlobal('fetch', failing);

    const first = await postOpened(token, 'visitor-dedupe-1');
    expect(first.status).toBe(204);
    await vi.waitFor(() => {
      expect(failing).toHaveBeenCalledTimes(1);
      expect(dedupeKeys()).toHaveLength(0);
    });
    expect(String(failing.mock.calls[0]?.[0])).toContain('api.push.apple.com');
    expect(rateLimitKeys().length).toBeGreaterThan(0);
    const rateKeysAfterFailure = rateLimitKeys();

    const retry = await postOpened(token, 'visitor-dedupe-1');
    expect(retry.status).toBe(204);
    await vi.waitFor(() => {
      expect(failing).toHaveBeenCalledTimes(2);
      expect(dedupeKeys()).toHaveLength(0);
    });
    expect(rateLimitKeys().length).toBeGreaterThanOrEqual(rateKeysAfterFailure.length);

    const succeeding = vi.fn(async (input: RequestInfo | URL) => {
      void input;
      return new Response('', { status: 200 });
    });
    vi.stubGlobal('fetch', succeeding);
    const sent = await postOpened(token, 'visitor-dedupe-1');
    expect(sent.status).toBe(204);
    await vi.waitFor(() => {
      expect(succeeding).toHaveBeenCalledTimes(1);
    });
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(dedupeKeys()).toHaveLength(1);

    const repeat = await postOpened(token, 'visitor-dedupe-1');
    expect(repeat.status).toBe(204);
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(succeeding).toHaveBeenCalledTimes(1);
    expect(dedupeKeys()).toHaveLength(1);
  });

  it('drops the visitor key when the APNs request rejects', async () => {
    const { token } = seedNotifyingLink();
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('network down');
      }),
    );

    const res = await postOpened(token, 'visitor-dedupe-2');
    expect(res.status).toBe(204);
    await vi.waitFor(() => {
      expect(dedupeKeys()).toHaveLength(0);
    });
    expect(rateLimitKeys().length).toBeGreaterThan(0);
  });
});
