import { describe, it, expect, beforeEach, vi } from 'vitest';
import { installDrizzleFake, resetStore, resetKv, store, TEST_ENV, ctx } from './support';

installDrizzleFake();

const apnsMocks = vi.hoisted(() => ({
  sendLinkOpenedNotification: vi.fn(async () => undefined),
}));

vi.mock('~/services/apns', () => ({
  sendLinkOpenedNotification: apnsMocks.sendLinkOpenedNotification,
  linkOpenedAlertBody: () => 'Opened in a browser',
}));

import worker from '~/index';

const BROWSER_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';

const PREVIEW_CLIENTS: Array<[string, string]> = [
  ['Slack', 'Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)'],
  ['WhatsApp', 'WhatsApp/2.23.20.0'],
  ['iMessage', 'facebookexternalhit/1.1'],
  ['Telegram', 'TelegramBot (like TwitterBot)'],
  ['LinkedIn', 'LinkedInBot/1.0 (compatible; Mozilla/5.0; Apache-HttpClient)'],
  ['Discord', 'Mozilla/5.0 (compatible; Discordbot/2.0; +https://discordapp.com)'],
  ['SkypeUriPreview', 'Mozilla/5.0 (Windows NT 6.1; WOW64) SkypeUriPreview Preview/0.5'],
  ['browser', BROWSER_UA],
];

async function fetchPath(
  path: string,
  init: RequestInit & { headers?: Record<string, string> } = {},
): Promise<Response> {
  const headers = new Headers(init.headers);
  if (!headers.has('user-agent')) headers.set('user-agent', BROWSER_UA);
  return worker.fetch(
    new Request(`https://fastsha.red${path}`, { ...init, headers, redirect: 'manual' }),
    TEST_ENV,
    ctx,
  );
}

function seedLink(overrides: { token?: string; notifyOnOpen?: boolean; filename?: string } = {}): {
  token: string;
  storageKey: string;
} {
  const token = overrides.token ?? 'openAlertTokenAAAAAAA';
  const assetId = crypto.randomUUID();
  const storageKey = `uploads/aa/2026/04/19/${assetId}.bin`;
  store.assets.push({
    id: assetId,
    ownerDeviceId: crypto.randomUUID(),
    bucket: 'b',
    storageKey,
    contentType: 'image/jpeg',
    sizeBytes: 128,
    sha256: null,
    originalFilename: overrides.filename ?? 'photo.jpg',
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
    notifyOnOpen: overrides.notifyOnOpen ?? true,
    maxAccessCount: null,
    createdAt: new Date(),
  });
  return { token, storageKey };
}

function seedBundle(token = 'bundleOpenTokenAAAAAA'): { token: string } {
  const bundleLinkId = crypto.randomUUID();
  const assetId = crypto.randomUUID();
  store.shareLinks.push({
    id: bundleLinkId,
    token,
    assetId: null,
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
    isBundle: true,
    bundleAssetCount: 1,
  });
  store.assets.push({
    id: assetId,
    ownerDeviceId: crypto.randomUUID(),
    bucket: 'b',
    storageKey: `uploads/aa/2026/04/19/${assetId}.bin`,
    contentType: 'text/plain',
    sizeBytes: 12,
    sha256: null,
    originalFilename: 'notes.txt',
    status: 'verified',
    createdAt: new Date(),
    verifiedAt: new Date(),
    deletedAt: null,
    deleteAfter: new Date(Date.now() + 86_400_000),
    deletionStatus: 'pending',
    deletionAttempts: 0,
    deletionLastError: null,
  });
  store.bundleAssets.push({
    id: crypto.randomUUID(),
    shareLinkId: bundleLinkId,
    assetId,
    uploadJobId: crypto.randomUUID(),
    displayOrder: 0,
    createdAt: new Date(),
  });
  return { token };
}

function installR2Fake(): void {
  const bytesByKey = new Map<string, Uint8Array>();
  (TEST_ENV as { R2: unknown }).R2 = {
    async get(key: string) {
      const bytes = bytesByKey.get(key);
      if (!bytes) return null;
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue(bytes);
          controller.close();
        },
      });
      return { body: stream, size: bytes.byteLength, etag: 'test-etag' };
    },
    async put(key: string, value: Uint8Array): Promise<void> {
      bytesByKey.set(key, value);
    },
  };
}

async function postOpened(
  token: string,
  visitor: string,
  userAgent = BROWSER_UA,
): Promise<Response> {
  return fetchPath(`/s/${token}/opened`, {
    method: 'POST',
    headers: {
      'user-agent': userAgent,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ visitor }),
  });
}

describe('open alert', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    installR2Fake();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    apnsMocks.sendLinkOpenedNotification.mockClear();
  });

  it.each(PREVIEW_CLIENTS)(
    'GET preview from %s sends no open alert',
    async (_name, userAgent) => {
      const { token } = seedLink();
      const res = await fetchPath(`/s/${token}`, {
        headers: { accept: 'text/html', 'user-agent': userAgent },
      });
      expect(res.status).toBe(200);
      expect(res.headers.get('Content-Type')).toMatch(/text\/html/);
      const html = await res.text();
      expect(html).toContain(`/s/${token}/opened`);
      expect(html).toContain('localStorage');
      expect(html).toContain('visibilityState');
      expect(html).toContain('1500');
      expect(res.headers.get('Content-Security-Policy')).toContain("connect-src 'self'");
      await vi.waitFor(() => {
        expect(store.shareLinks[0]?.accessCount).toBe(1);
      });
      expect(apnsMocks.sendLinkOpenedNotification).not.toHaveBeenCalled();
    },
  );

  it('a browser beacon sends one alert and a repeat from the same visitor does not', async () => {
    const { token } = seedLink({ filename: 'photo.jpg' });
    const visitor = 'browser-visitor-1';

    const first = await postOpened(token, visitor);
    expect(first.status).toBe(204);
    await vi.waitFor(() => {
      expect(apnsMocks.sendLinkOpenedNotification).toHaveBeenCalledTimes(1);
    });
    const call = apnsMocks.sendLinkOpenedNotification.mock.calls[0] as
      | [Record<string, unknown>]
      | undefined;
    expect(call?.[0]).toMatchObject({
      token,
      filename: 'photo.jpg',
      shortUrl: `https://fastsha.red/s/${token}`,
    });

    const second = await postOpened(token, visitor);
    expect(second.status).toBe(204);
    await Promise.resolve();
    expect(apnsMocks.sendLinkOpenedNotification).toHaveBeenCalledTimes(1);
  });

  it('a beacon with an unfurler user agent sends no alert', async () => {
    const { token } = seedLink();
    const res = await postOpened(token, 'robot-visitor-1', 'Slackbot-LinkExpanding 1.0');
    expect(res.status).toBe(204);
    await Promise.resolve();
    expect(apnsMocks.sendLinkOpenedNotification).not.toHaveBeenCalled();
  });

  it('a file download does not send an alert', async () => {
    const { token, storageKey } = seedLink();
    const r2 = TEST_ENV.R2 as unknown as {
      put: (key: string, value: Uint8Array) => Promise<void>;
    };
    await r2.put(storageKey, new Uint8Array([1, 2, 3, 4]));

    const res = await fetchPath(`/s/${token}/download`, { headers: { accept: '*/*' } });
    expect(res.status).toBe(200);
    await res.arrayBuffer();
    await vi.waitFor(() => {
      expect(store.shareLinks[0]?.accessCount).toBe(1);
    });
    expect(apnsMocks.sendLinkOpenedNotification).not.toHaveBeenCalled();
  });

  it('a bundle preview beacons the same opened endpoint and alerts once', async () => {
    const { token } = seedBundle();
    const page = await fetchPath(`/b/${token}`, { headers: { accept: 'text/html' } });
    expect(page.status).toBe(200);
    const html = await page.text();
    expect(html).toContain(`/s/${token}/opened`);
    expect(html).toContain('visibilityState');
    expect(html).toContain('localStorage');
    await vi.waitFor(() => {
      expect(store.shareLinks[0]?.accessCount).toBe(1);
    });
    expect(apnsMocks.sendLinkOpenedNotification).not.toHaveBeenCalled();

    const opened = await postOpened(token, 'bundle-visitor-1');
    expect(opened.status).toBe(204);
    await vi.waitFor(() => {
      expect(apnsMocks.sendLinkOpenedNotification).toHaveBeenCalledTimes(1);
    });
    const call = apnsMocks.sendLinkOpenedNotification.mock.calls[0] as
      | [Record<string, unknown>]
      | undefined;
    expect(call?.[0]).toMatchObject({
      token,
      filename: 'notes.txt',
      shortUrl: `https://fastsha.red/b/${token}`,
    });
  });

  it('does not alert when notify is off, the visitor id is missing, or the token is inactive', async () => {
    const quiet = seedLink({ token: 'quietTokenAAAAAAAAAAA', notifyOnOpen: false });
    const quietRes = await postOpened(quiet.token, 'quiet-visitor-1');
    expect(quietRes.status).toBe(204);

    const { token } = seedLink({ token: 'strictTokenAAAAAAAAAA' });
    const missing = await fetchPath(`/s/${token}/opened`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({}),
    });
    expect(missing.status).toBe(400);

    const unknown = await postOpened('missingTokenAAAAAAAAA', 'missing-visitor-1');
    expect(unknown.status).toBe(404);

    expect(apnsMocks.sendLinkOpenedNotification).not.toHaveBeenCalled();
  });

  it('rate limits opened beacons per IP and token', async () => {
    const { token } = seedLink();
    for (let i = 0; i < 30; i++) {
      const res = await postOpened(token, `visitor-${i.toString().padStart(4, '0')}`);
      expect(res.status).toBe(204);
    }
    const blocked = await postOpened(token, 'visitor-0030');
    expect(blocked.status).toBe(429);
  });
});
