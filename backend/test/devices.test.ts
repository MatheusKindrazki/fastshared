import { describe, expect, it, beforeEach, vi } from 'vitest';
import { installDrizzleFake, resetKv, resetStore, store, TEST_ENV, ctx } from './support';

installDrizzleFake();

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

describe('POST /v1/devices', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('registers a CLI device token and accepts it for uploads', async () => {
    const register = await post('/v1/devices', {
      platform: 'cli',
      appVersion: 'fastshared-cli/0.1.0',
    });

    expect(register.status).toBe(201);
    const registered = (await register.json()) as { deviceId: string; deviceToken: string };
    expect(registered.deviceId).toBeTruthy();
    expect(registered.deviceToken).toBeTruthy();
    expect(store.devices).toHaveLength(1);
    expect(store.devices[0]?.platform).toBe('cli');

    const upload = await post(
      '/v1/uploads',
      {
        clientJobId: crypto.randomUUID(),
        contentType: 'text/plain',
        sizeBytes: 11,
        sha256: '64ec88ca00b268e5ba1a35678a1b5316d212f4f366b2477232534a8aeca37f3c',
        originalFilename: 'hello.txt',
        retentionPolicy: 'oneHour',
      },
      { authorization: `Bearer ${registered.deviceToken}` },
    );

    expect(upload.status).toBe(200);
    const body = (await upload.json()) as { uploadId?: string; shortUrl?: string };
    expect(body.uploadId).toBeTruthy();
    expect(body.shortUrl).toMatch(/^https:\/\/fastsha\.red\/s\//);
  });

  it('rejects unknown platforms', async () => {
    const res = await post('/v1/devices', {
      platform: 'linux',
      appVersion: 'fastshared-cli/0.1.0',
    });

    expect(res.status).toBe(400);
    expect(store.devices).toHaveLength(0);
  });

  it('updates APNs token for the authenticated device', async () => {
    const register = await post('/v1/devices', {
      platform: 'ios',
      appVersion: '1.0.0',
    });
    expect(register.status).toBe(201);
    const registered = (await register.json()) as { deviceToken: string };

    const res = await post(
      '/v1/devices/push-token',
      {
        apnsToken: 'A'.repeat(64),
        environment: 'production',
      },
      { authorization: `Bearer ${registered.deviceToken}` },
    );

    expect(res.status).toBe(200);
    expect(store.devices[0]?.apnsToken).toBe('a'.repeat(64));
    expect(store.devices[0]?.apnsEnvironment).toBe('production');
    expect(store.devices[0]?.apnsUpdatedAt).toBeInstanceOf(Date);
  });
});
