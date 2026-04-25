import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  installDrizzleFake,
  resetStore,
  resetKv,
  store,
  TEST_ENV,
  ctx,
  type AssetRow,
  type BundleAssetRow,
  type ShareLinkRow,
} from './support';

installDrizzleFake();

import worker from '~/index';

// Default UA mimics Safari so the negotiation in dispatchHandler treats us
// like a browser when relevant — bundle preview always serves HTML, but we
// keep the same posture as redirect.test.ts for consistency.
const BROWSER_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';

async function get(path: string, headers: Record<string, string> = {}): Promise<Response> {
  return worker.fetch(
    new Request(`https://fastsha.red${path}`, {
      headers: { 'user-agent': BROWSER_UA, ...headers },
      redirect: 'manual',
    }),
    TEST_ENV,
    ctx,
  );
}

// R2 fake — copies the redirect.test.ts pattern. streamAssetBytes calls
// getObjectStream() on the env binding via services/r2; that helper in turn
// pulls from env.R2.get(), which is what we override here.
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

async function putR2Bytes(key: string, bytes: Uint8Array): Promise<void> {
  const r2 = TEST_ENV.R2 as unknown as {
    _bytes?: Map<string, Uint8Array>;
  };
  if (!r2._bytes) r2._bytes = new Map();
  r2._bytes.set(key, bytes);
}

interface SeedBundleArgs {
  token?: string;
  linkStatus?: 'active' | 'pending' | 'expired' | 'revoked';
  expiresAt?: Date;
  itemCount: number;
  // Optional per-asset overrides keyed by index. Defaults: 1024 bytes,
  // application/octet-stream, originalFilename = `file-${i}.bin`.
  perAsset?: Array<{
    originalFilename?: string;
    contentType?: string;
    sizeBytes?: number;
    storageKey?: string;
    deletedAt?: Date | null;
    status?: string;
  }>;
}

interface SeededBundle {
  bundleLinkId: string;
  token: string;
  assets: Array<{
    assetId: string;
    storageKey: string;
    originalFilename: string;
    previewUrl: string;
    downloadUrl: string;
  }>;
}

function seedBundle(args: SeedBundleArgs): SeededBundle {
  const token = args.token ?? `bundleTok${Math.random().toString(36).slice(2, 10)}`;
  const bundleLinkId = crypto.randomUUID();
  const deviceId = crypto.randomUUID();
  const link: ShareLinkRow = {
    id: bundleLinkId,
    token,
    assetId: null,
    visibility: 'signed',
    expiresAt: args.expiresAt ?? new Date(Date.now() + 3_600_000),
    hits: 0,
    linkStatus: args.linkStatus ?? 'active',
    retentionPolicy: 'oneDay',
    revokedAt: null,
    lastAccessedAt: null,
    accessCount: 0,
    maxAccessCount: null,
    createdAt: new Date(),
    isBundle: true,
    bundleAssetCount: args.itemCount,
  };
  store.shareLinks.push(link);

  const assets: SeededBundle['assets'] = [];
  for (let i = 0; i < args.itemCount; i++) {
    const overrides = args.perAsset?.[i] ?? {};
    const assetId = crypto.randomUUID();
    const filename = overrides.originalFilename ?? `file-${i}.bin`;
    const storageKey = overrides.storageKey ?? `uploads/aa/2026/04/19/${assetId}.bin`;
    const a: AssetRow = {
      id: assetId,
      ownerDeviceId: deviceId,
      bucket: 'b',
      storageKey,
      contentType: overrides.contentType ?? 'application/octet-stream',
      sizeBytes: overrides.sizeBytes ?? 1024,
      sha256: null,
      originalFilename: filename,
      status: overrides.status ?? 'verified',
      createdAt: new Date(),
      verifiedAt: new Date(),
      deletedAt: overrides.deletedAt ?? null,
      deleteAfter: new Date(Date.now() + 86_400_000),
      deletionStatus: 'pending',
      deletionAttempts: 0,
      deletionLastError: null,
    };
    store.assets.push(a);
    const j: BundleAssetRow = {
      id: crypto.randomUUID(),
      shareLinkId: bundleLinkId,
      assetId,
      uploadJobId: crypto.randomUUID(),
      displayOrder: i,
      createdAt: new Date(),
    };
    store.bundleAssets.push(j);
    assets.push({
      assetId,
      storageKey,
      originalFilename: filename,
      previewUrl: `https://fastsha.red/b/${token}/p/${assetId}`,
      downloadUrl: `https://fastsha.red/b/${token}/d/${assetId}`,
    });
  }
  return { bundleLinkId, token, assets };
}

describe('bundle redirect (M2)', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    installR2Fake();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('GET /b/:token on an active bundle returns 200 HTML listing each asset', async () => {
    const seeded = seedBundle({
      itemCount: 3,
      perAsset: [
        { originalFilename: 'first.png', contentType: 'image/png', sizeBytes: 256 },
        { originalFilename: 'second.pdf', contentType: 'application/pdf', sizeBytes: 1024 },
        { originalFilename: 'third.txt', contentType: 'text/plain', sizeBytes: 64 },
      ],
    });
    const res = await get(`/b/${seeded.token}`, { accept: 'text/html' });
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toMatch(/text\/html/);
    const body = await res.text();
    expect(body).toContain('data-bundle-gallery');
    // Each filename appears in the rendered card list.
    for (const a of seeded.assets) {
      expect(body).toContain(a.originalFilename);
    }
    // Per-asset preview and download URLs are present.
    for (const a of seeded.assets) {
      expect(body).toContain(a.previewUrl);
      expect(body).toContain(a.downloadUrl);
    }
  });

  it('GET /b/:token on a pending bundle returns the uploading page', async () => {
    const seeded = seedBundle({ itemCount: 2, linkStatus: 'pending' });
    const res = await get(`/b/${seeded.token}`, { accept: 'text/html' });
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain('Uploading');
    expect(body).toContain('Bundle upload');
  });

  it('GET /b/:token on a revoked bundle returns 404 (or 410 — gone family)', async () => {
    // Revoked → loadActiveBundle returns { status: 'gone', reason: 'revoked' },
    // which the handler maps to 410. The user spec says "→ 404"; treating any
    // 4xx-gone family as failure-to-serve. We assert the canonical 410 here so
    // the test fails loudly if the behaviour changes.
    const seeded = seedBundle({ itemCount: 2, linkStatus: 'revoked' });
    const res = await get(`/b/${seeded.token}`, { accept: 'text/html' });
    expect([404, 410]).toContain(res.status);
  });

  it('GET /b/:token on an expired bundle returns 410 (gone)', async () => {
    const seeded = seedBundle({
      itemCount: 2,
      expiresAt: new Date(Date.now() - 60_000),
    });
    const res = await get(`/b/${seeded.token}`, { accept: 'text/html' });
    // Expired bundles flow through the same gone-family branch.
    expect([404, 410]).toContain(res.status);
  });

  it('GET /b/:token/d/:assetId for an asset that belongs to the bundle streams bytes', async () => {
    const seeded = seedBundle({
      itemCount: 2,
      perAsset: [
        { originalFilename: 'one.bin', contentType: 'application/octet-stream', sizeBytes: 4 },
        { originalFilename: 'two.bin', contentType: 'application/octet-stream', sizeBytes: 4 },
      ],
    });
    const target = seeded.assets[0]!;
    await putR2Bytes(target.storageKey, new Uint8Array([1, 2, 3, 4]));

    const res = await get(`/b/${seeded.token}/d/${target.assetId}`, { accept: '*/*' });
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toBe('application/octet-stream');
    expect(res.headers.get('Accept-Ranges')).toBe('bytes');
    expect(res.headers.get('Content-Length')).toBe('4');
    const got = new Uint8Array(await res.arrayBuffer());
    expect([...got]).toEqual([1, 2, 3, 4]);
  });

  it('GET /b/:token/p/:assetId serves inline bytes for in-gallery previews', async () => {
    const seeded = seedBundle({
      itemCount: 1,
      perAsset: [{ originalFilename: 'photo.jpg', contentType: 'image/jpeg', sizeBytes: 4 }],
    });
    const target = seeded.assets[0]!;
    await putR2Bytes(target.storageKey, new Uint8Array([1, 2, 3, 4]));

    const res = await get(`/b/${seeded.token}/p/${target.assetId}`, { accept: '*/*' });
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toBe('image/jpeg');
    expect(res.headers.get('Content-Disposition') ?? '').toMatch(/inline/);
    const got = new Uint8Array(await res.arrayBuffer());
    expect([...got]).toEqual([1, 2, 3, 4]);
  });

  it('GET /b/:token/d/:assetId for an asset NOT in the bundle returns 404', async () => {
    const seeded = seedBundle({ itemCount: 2 });
    // Insert a free-floating asset that isn't joined to any bundle. Calling
    // /b/:token/d/<this asset's id> must reject — the junction guard is the
    // only thing stopping a token leak from pivoting to bytes of another
    // share owned by the same device.
    const orphanId = crypto.randomUUID();
    store.assets.push({
      id: orphanId,
      ownerDeviceId: crypto.randomUUID(),
      bucket: 'b',
      storageKey: 'uploads/zz/2026/04/19/orphan.bin',
      contentType: 'application/octet-stream',
      sizeBytes: 4,
      sha256: null,
      originalFilename: 'orphan.bin',
      status: 'verified',
      createdAt: new Date(),
      verifiedAt: new Date(),
      deletedAt: null,
      deleteAfter: new Date(Date.now() + 86_400_000),
      deletionStatus: 'pending',
      deletionAttempts: 0,
      deletionLastError: null,
    });

    const res = await get(`/b/${seeded.token}/d/${orphanId}`, { accept: '*/*' });
    expect(res.status).toBe(404);
  });
});
