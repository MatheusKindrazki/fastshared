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

import worker from '~/index';

async function get(path: string, headers: Record<string, string> = {}): Promise<Response> {
  return worker.fetch(
    new Request(`https://fastsha.red${path}`, { headers, redirect: 'manual' }),
    TEST_ENV,
    ctx,
  );
}

async function head(path: string, headers: Record<string, string> = {}): Promise<Response> {
  return worker.fetch(
    new Request(`https://fastsha.red${path}`, { method: 'HEAD', headers, redirect: 'manual' }),
    TEST_ENV,
    ctx,
  );
}

function seedLinkAndAsset(overrides: {
  token?: string;
  linkStatus?: 'active' | 'expired' | 'revoked';
  expiresAt?: Date;
  deletedAt?: Date | null;
  originalFilename?: string | null;
  contentType?: string;
  sizeBytes?: number;
  storageKey?: string;
} = {}): { token: string; assetId: string; storageKey: string } {
  const token = overrides.token ?? 'liveTokenAAAAAAAAAAAAA';
  const assetId = crypto.randomUUID();
  const deviceId = crypto.randomUUID();
  const storageKey = overrides.storageKey ?? `uploads/aa/2026/04/19/${assetId}.bin`;
  const sizeBytes = overrides.sizeBytes ?? 1024;
  store.assets.push({
    id: assetId,
    ownerDeviceId: deviceId,
    bucket: 'b',
    storageKey,
    contentType: overrides.contentType ?? 'application/octet-stream',
    sizeBytes,
    sha256: null,
    originalFilename: overrides.originalFilename ?? 'example.bin',
    status: 'verified',
    createdAt: new Date(),
    verifiedAt: new Date(),
    deletedAt: overrides.deletedAt ?? null,
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
    expiresAt: overrides.expiresAt ?? new Date(Date.now() + 3_600_000),
    hits: 0,
    linkStatus: overrides.linkStatus ?? 'active',
    retentionPolicy: 'oneDay',
    revokedAt: null,
    lastAccessedAt: null,
    accessCount: 0,
    maxAccessCount: null,
    createdAt: new Date(),
  });
  return { token, assetId, storageKey };
}

async function putR2Bytes(key: string, bytes: Uint8Array): Promise<void> {
  // Mock R2 binding on the shared TEST_ENV — Miniflare gives us a real one,
  // but for this test we want full control so we set a property that R2's
  // `.get` method reads.
  const r2 = TEST_ENV.R2 as unknown as {
    _bytes?: Map<string, Uint8Array>;
    get: (key: string, opts?: { range?: unknown }) => unknown;
    put: (key: string, value: Uint8Array) => Promise<void>;
  };
  if (!r2._bytes) r2._bytes = new Map();
  r2._bytes.set(key, bytes);
}

function installR2Fake(): void {
  const bytesByKey = new Map<string, Uint8Array>();
  (TEST_ENV as { R2: unknown }).R2 = {
    _bytes: bytesByKey,
    async get(
      key: string,
      opts?: { range?: { offset?: number; length?: number; suffix?: number } },
    ) {
      const bytes = bytesByKey.get(key);
      if (!bytes) return null;
      let view: Uint8Array = bytes;
      const range = opts?.range;
      if (range) {
        if (typeof range.suffix === 'number') {
          const start = Math.max(0, bytes.byteLength - range.suffix);
          view = bytes.slice(start);
        } else if (typeof range.offset === 'number') {
          const start = range.offset;
          const len = range.length ?? bytes.byteLength - start;
          view = bytes.slice(start, start + len);
        }
      }
      // Use a fresh ReadableStream so the caller can pipe it.
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue(view);
          controller.close();
        },
      });
      return {
        body: stream,
        size: bytes.byteLength,
        etag: 'test-etag',
        httpMetadata: undefined,
        range,
      };
    },
    async put(key: string, value: Uint8Array): Promise<void> {
      bytesByKey.set(key, value);
    },
  };
}

describe('redirect proxy', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    installR2Fake();
    // Silence `log` noise from Hono's logger middleware.
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('HTML Accept returns 200 with preview page + OG tags', async () => {
    const { token } = seedLinkAndAsset({
      originalFilename: 'photo.jpg',
      contentType: 'image/jpeg',
      sizeBytes: 4096,
    });
    const res = await get(`/s/${token}`, { accept: 'text/html' });
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toMatch(/text\/html/);
    expect(res.headers.get('Cache-Control')).toBe('private, no-store');
    expect(res.headers.get('X-Content-Type-Options')).toBe('nosniff');
    const body = await res.text();
    expect(body).toContain('<meta property="og:title"');
    expect(body).toContain('data-expires-at="');
    expect(body).toContain('photo.jpg');
  });

  it('non-HTML Accept streams the bytes with attachment disposition', async () => {
    const { token, storageKey } = seedLinkAndAsset({
      originalFilename: 'report.pdf',
      contentType: 'application/pdf',
      sizeBytes: 8,
    });
    const bytesRef = [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34]; // %PDF-1.4
    await putR2Bytes(storageKey, new Uint8Array(bytesRef));

    const res = await get(`/s/${token}`, { accept: '*/*' });
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toBe('application/pdf');
    expect(res.headers.get('Accept-Ranges')).toBe('bytes');
    expect(res.headers.get('Content-Length')).toBe('8');
    expect(res.headers.get('Content-Disposition') ?? '').toMatch(/filename\*=UTF-8''/);
    expect(res.body).toBeInstanceOf(ReadableStream);
    const got = new Uint8Array(await res.arrayBuffer());
    expect([...got]).toEqual(bytesRef);
  });

  it('range request returns 206 with Content-Range', async () => {
    const { token, storageKey } = seedLinkAndAsset({
      contentType: 'application/octet-stream',
      sizeBytes: 200,
    });
    const bytes = new Uint8Array(200);
    for (let i = 0; i < 200; i++) bytes[i] = i & 0xff;
    await putR2Bytes(storageKey, bytes);

    const res = await get(`/s/${token}`, { accept: '*/*', range: 'bytes=0-99' });
    expect(res.status).toBe(206);
    expect(res.headers.get('Content-Range')).toBe('bytes 0-99/200');
    expect(res.headers.get('Content-Length')).toBe('100');
    const got = new Uint8Array(await res.arrayBuffer());
    expect(got.byteLength).toBe(100);
    expect(got[0]).toBe(0);
    expect(got[99]).toBe(99);
  });

  it('unsatisfiable range returns 416 with Content-Range', async () => {
    const { token, storageKey } = seedLinkAndAsset({ sizeBytes: 10 });
    await putR2Bytes(storageKey, new Uint8Array(10));
    const res = await get(`/s/${token}`, { accept: '*/*', range: 'bytes=999999999-' });
    expect(res.status).toBe(416);
    expect(res.headers.get('Content-Range')).toBe('bytes */10');
  });

  it('expired link (HTML Accept) → 410 HTML gone page', async () => {
    const { token } = seedLinkAndAsset({
      token: 'expiredTokenAAAAAAAAAA',
      expiresAt: new Date(Date.now() - 60_000),
    });
    const res = await get(`/s/${token}`, { accept: 'text/html' });
    expect(res.status).toBe(410);
    expect(res.headers.get('Content-Type')).toMatch(/text\/html/);
    const body = await res.text();
    expect(body.toLowerCase()).toContain('expired');
  });

  it('expired link (JSON Accept) → 410 problem+json', async () => {
    const { token } = seedLinkAndAsset({
      token: 'expiredJsonAAAAAAAAAAA',
      expiresAt: new Date(Date.now() - 60_000),
    });
    const res = await get(`/s/${token}`, { accept: 'application/json' });
    expect(res.status).toBe(410);
    expect(res.headers.get('Content-Type')).toMatch(/application\/problem\+json/);
  });

  it('revoked link returns 410 in both content negotiations', async () => {
    const { token } = seedLinkAndAsset({
      token: 'revokedTokenAAAAAAAAAA',
      linkStatus: 'revoked',
    });
    const resHtml = await get(`/s/${token}`, { accept: 'text/html' });
    expect(resHtml.status).toBe(410);
    const resJson = await get(`/s/${token}`, { accept: 'application/json' });
    expect(resJson.status).toBe(410);
  });

  it('unknown token returns 404 in both content negotiations', async () => {
    const resHtml = await get('/s/doesnotexist', { accept: 'text/html' });
    expect(resHtml.status).toBe(404);
    const resJson = await get('/s/doesnotexist', { accept: 'application/json' });
    expect(resJson.status).toBe(404);
  });

  it('HEAD /:token returns 200 with binary headers, empty body', async () => {
    const { token, storageKey } = seedLinkAndAsset({ sizeBytes: 16 });
    await putR2Bytes(storageKey, new Uint8Array(16));
    const res = await head(`/s/${token}`);
    expect(res.status).toBe(200);
    expect(res.headers.get('Accept-Ranges')).toBe('bytes');
    expect(res.headers.get('Content-Length')).toBe('16');
    const body = await res.text();
    expect(body).toBe('');
  });

  it('?dl=1 on HTML Accept still streams binary', async () => {
    const { token, storageKey } = seedLinkAndAsset({ sizeBytes: 4 });
    await putR2Bytes(storageKey, new Uint8Array([1, 2, 3, 4]));
    const res = await get(`/s/${token}?dl=1`, { accept: 'text/html' });
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toBe('application/octet-stream');
    expect(res.headers.get('Accept-Ranges')).toBe('bytes');
  });

  it('binary path returns a ReadableStream (never buffered)', async () => {
    const { token, storageKey } = seedLinkAndAsset({ sizeBytes: 4 });
    await putR2Bytes(storageKey, new Uint8Array([9, 8, 7, 6]));
    const res = await get(`/s/${token}/download`);
    expect(res.status).toBe(200);
    expect(res.body).toBeInstanceOf(ReadableStream);
  });
});
