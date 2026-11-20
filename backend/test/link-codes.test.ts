import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
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

vi.mock('jose', () => ({
  importPKCS8: vi.fn(async () => ({})),
  SignJWT: class {
    setProtectedHeader() {
      return this;
    }
    setIssuer() {
      return this;
    }
    setIssuedAt() {
      return this;
    }
    async sign() {
      return 'jwt';
    }
  },
}));

import worker from '~/index';
import { sendLinkOpenedNotification } from '~/services/apns';
import { createDb } from '~/db/client';

function post(path: string, token: string, body?: unknown, ip = '203.0.113.7'): Promise<Response> {
  return worker.fetch(
    new Request(`https://api.fastsha.red${path}`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
        'cf-connecting-ip': ip,
      },
      body: body === undefined ? null : JSON.stringify(body),
    }),
    TEST_ENV,
    ctx,
  );
}

function deviceRow(id: string) {
  return store.devices.find((d) => d.id === id)!;
}

async function appDeviceWithUser(): Promise<{ deviceId: string; token: string; userId: string }> {
  const userId = crypto.randomUUID();
  store.users.push({ id: userId, appleUserId: 'apple-1', email: null } as never);
  const seeded = await seedDevice({ token: `app-${crypto.randomUUID()}` });
  deviceRow(seeded.deviceId).userId = userId;
  return { ...seeded, userId };
}

describe('device link codes', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
  });

  it('refuses to create a code on a device that is not signed in', async () => {
    const { token } = await seedDevice({ token: 'anon-device-token' });
    const res = await post('/v1/link-codes', token);
    expect(res.status).toBe(409);
    expect(((await res.json()) as { code: string }).code).toBe('sign_in_required');
  });

  it('links a CLI device to the app account exactly once', async () => {
    const app = await appDeviceWithUser();
    const created = await post('/v1/link-codes', app.token);
    expect(created.status).toBe(201);
    const { code, expiresAt } = (await created.json()) as { code: string; expiresAt: string };
    expect(code).toMatch(/^\d{6}$/);
    expect(new Date(expiresAt).getTime()).toBeGreaterThan(Date.now());
    expect(JSON.stringify(store.deviceLinkCodes)).not.toContain(code);

    const cli = await seedDevice({ token: 'cli-device-token' });
    deviceRow(cli.deviceId).platform = 'cli';
    const claimed = await post('/v1/link-codes/claim', cli.token, { code });
    expect(claimed.status).toBe(200);
    expect(await claimed.json()).toEqual({ linked: true, userId: app.userId });
    expect(deviceRow(cli.deviceId).userId).toBe(app.userId);

    const again = await seedDevice({ token: 'second-cli-token' });
    const reused = await post('/v1/link-codes/claim', again.token, { code });
    expect(reused.status).toBe(400);
    expect(deviceRow(again.deviceId).userId).toBeNull();
  });

  it('rejects an expired code', async () => {
    const app = await appDeviceWithUser();
    const { code } = (await (await post('/v1/link-codes', app.token)).json()) as { code: string };
    store.deviceLinkCodes[0]!.expiresAt = new Date(Date.now() - 1000);
    const cli = await seedDevice({ token: 'late-cli-token' });
    const res = await post('/v1/link-codes/claim', cli.token, { code });
    expect(res.status).toBe(400);
    expect(deviceRow(cli.deviceId).userId).toBeNull();
  });

  it('rejects malformed codes without touching the store', async () => {
    const cli = await seedDevice({ token: 'bad-format-token' });
    for (const code of ['12345', '1234567', 'abcdef']) {
      const res = await post('/v1/link-codes/claim', cli.token, { code });
      expect(res.status).toBe(400);
    }
  });

  it('does not move a device that already belongs to another account', async () => {
    const app = await appDeviceWithUser();
    const { code } = (await (await post('/v1/link-codes', app.token)).json()) as { code: string };
    const other = await seedDevice({ token: 'other-account-token' });
    deviceRow(other.deviceId).userId = crypto.randomUUID();
    const res = await post('/v1/link-codes/claim', other.token, { code });
    expect(res.status).toBe(409);
  });

  it('throttles repeated claims from one device', async () => {
    const cli = await seedDevice({ token: 'guessing-device' });
    const statuses: number[] = [];
    for (let i = 0; i < 7; i++) {
      statuses.push((await post('/v1/link-codes/claim', cli.token, { code: '000000' })).status);
    }
    expect(statuses.slice(0, 5).every((s) => s === 400)).toBe(true);
    expect(statuses.slice(5)).toContain(429);
  });

  it('accepts web devices at registration', async () => {
    const res = await worker.fetch(
      new Request('https://api.fastsha.red/v1/devices', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'cf-connecting-ip': '198.51.100.4' },
        body: JSON.stringify({ platform: 'web', appVersion: 'web' }),
      }),
      TEST_ENV,
      ctx,
    );
    expect(res.status).toBe(201);
  });
});

describe('open alerts reach every device of the account', () => {
  const env = {
    ...TEST_ENV,
    APNS_KEY_ID: 'KEY',
    APNS_TEAM_ID: 'TEAM',
    APNS_P8_KEY_BASE64: btoa('pem'),
  };

  beforeEach(() => resetStore());
  afterEach(() => vi.unstubAllGlobals());

  it('pings the iPhone when the link was created by a linked CLI device', async () => {
    const userId = crypto.randomUUID();
    const phone = await seedDevice({ token: 'phone-token' });
    Object.assign(deviceRow(phone.deviceId), {
      userId,
      apnsToken: 'a'.repeat(64),
      apnsEnvironment: 'production',
    });
    const cli = await seedDevice({ token: 'cli-token' });
    Object.assign(deviceRow(cli.deviceId), { userId, platform: 'cli' });

    const pushes: string[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        pushes.push(url);
        return new Response(null, { status: 200 });
      }),
    );

    const sent = await sendLinkOpenedNotification({
      env,
      db: createDb(env.DATABASE_URL),
      deviceId: cli.deviceId,
      token: 'abc',
      filename: 'report.html',
      shortUrl: 'https://p-abcdefghij.fastsha.red',
    });
    expect(sent).toBe(true);
    expect(pushes).toEqual([`https://api.push.apple.com/3/device/${'a'.repeat(64)}`]);
  });

  it('sends nothing for an unlinked device without a push token', async () => {
    const cli = await seedDevice({ token: 'lonely-cli' });
    const fetchSpy = vi.fn();
    vi.stubGlobal('fetch', fetchSpy);
    const sent = await sendLinkOpenedNotification({
      env,
      db: createDb(env.DATABASE_URL),
      deviceId: cli.deviceId,
      token: 'abc',
      shortUrl: 'https://fastsha.red/s/abc',
    });
    expect(sent).toBe(false);
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
