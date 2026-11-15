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

installDrizzleFake();
vi.mock('~/services/r2', async (importOriginal) => ({
  ...(await importOriginal<typeof import('~/services/r2')>()),
  presignPut: vi.fn(async () => ({
    url: 'https://upload.test/object',
    method: 'PUT',
    headers: { 'content-type': 'application/zip' },
    expiresAt: new Date().toISOString(),
  })),
}));

import worker, { withoutDomainCookies } from '~/index';
import { strToU8, zipSync } from 'fflate';

let token: string;
let objects: Map<string, Uint8Array>;
let writes: string[];

async function api(path: string, method = 'GET', body?: unknown) {
  return worker.fetch(
    new Request(`https://api.fastsha.red/v1/publications${path === '/' ? '' : path}`, {
      method,
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }),
    TEST_ENV,
    ctx,
  );
}

beforeEach(async () => {
  resetStore();
  resetKv();
  TEST_ENV.PUBLICATION_HOST_SUFFIX = 'fastsha.red';
  objects = new Map();
  writes = [];
  TEST_ENV.PUBLICATIONS = {
    async get(key: string, opts?: { range?: { offset: number; length: number } }) {
      const all = objects.get(key);
      if (!all) return null;
      const bytes = opts?.range
        ? all.slice(opts.range.offset, opts.range.offset + opts.range.length)
        : all;
      return {
        size: all.length,
        body: new Response(bytes as unknown as BodyInit).body!,
        arrayBuffer: async () =>
          bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
      };
    },
    async put(key: string, body: ReadableStream<Uint8Array>) {
      objects.set(key, new Uint8Array(await new Response(body).arrayBuffer()));
      writes.push(key);
    },
    async delete(key: string | string[]) {
      for (const k of Array.isArray(key) ? key : [key]) objects.delete(k);
    },
    async list(opts: { prefix: string }) {
      return {
        objects: [...objects.keys()]
          .filter((k) => k.startsWith(opts.prefix))
          .map((key) => ({ key })),
        truncated: false,
      };
    },
  } as unknown as R2Bucket;
  token = (await seedDevice()).token;
  class TestHtmlRewriter {
    private handlers: Record<
      string,
      { element: (el: { prepend: (s: string) => void; append: (s: string) => void }) => void }
    > = {};
    on(
      tag: string,
      handler: {
        element: (el: { prepend: (s: string) => void; append: (s: string) => void }) => void;
      },
    ) {
      this.handlers[tag] = handler;
      return this;
    }
    async transform(res: Response) {
      let html = await res.text();
      for (const [tag, handler] of Object.entries(this.handlers)) {
        let before = '';
        let after = '';
        handler.element({
          prepend: (s) => {
            before += s;
          },
          append: (s) => {
            after += s;
          },
        });
        html = html
          .replace(`<${tag}>`, `<${tag}>${before}`)
          .replace(`</${tag}>`, `${after}</${tag}>`);
      }
      return new Response(html, { status: res.status, headers: res.headers });
    }
  }
  Object.assign(globalThis, { HTMLRewriter: TestHtmlRewriter });
});

describe('publications API contract', () => {
  const input = {
    title: 'Report',
    kind: 'site',
    filename: 'site.zip',
    sizeBytes: 0,
    contentType: 'application/zip',
  };

  it('creates, completes, lists, and revokes a Free site', async () => {
    const zip = zipSync({
      'index.html': strToU8(
        '<html><head></head><body><script src="./assets/app.js"></script></body></html>',
      ),
      'assets/app.js': strToU8('ok'),
    });
    const created = await api('/', 'POST', { ...input, sizeBytes: zip.length });
    expect(created.status).toBe(201);
    const body = (await created.json()) as any;
    expect(body).toMatchObject({
      id: expect.any(String),
      slug: expect.stringMatching(/^[a-z2-7]{10}$/),
      url: expect.stringMatching(/^https:\/\/p-/),
      version: 1,
      upload: { url: 'https://upload.test/object', method: 'PUT', headers: expect.any(Object) },
    });
    objects.set(`pub/${body.id}/v1/_source`, zip);
    const completed = await api(`/${body.id}/versions/1/complete`, 'POST');
    expect(completed.status).toBe(200);
    expect(await completed.json()).toMatchObject({ url: body.url, version: 1, fileCount: 2 });
    expect(objects.has(`pub/${body.id}/v1/assets/app.js`)).toBe(true);
    const page = await worker.fetch(
      new Request(body.url, { headers: { 'user-agent': 'Mozilla/5.0 Safari/605' } }),
      TEST_ENV,
      ctx,
    );
    expect(page.status).toBe(200);
    const html = await page.text();
    expect(html).toContain('./assets/app.js');
    expect(html).toContain("fetch('/opened'");
    expect(html).toContain('Hosted with FastShared');
    expect(html).toContain('/v1/abuse-reports?publication=');
    const asset = await worker.fetch(new Request(`${body.url}/assets/app.js`), TEST_ENV, ctx);
    expect(await asset.text()).toBe('ok');
    const listed = await api('/');
    for (const res of [created, completed, listed, page, asset])
      expect(res.headers.get('set-cookie') ?? '').not.toMatch(/Domain=\.fastsha\.red/i);
    expect(((await listed.json()) as any).publications[0]).toMatchObject({
      id: body.id,
      status: 'active',
      currentVersion: 1,
      opensLast7Days: 0,
    });
    expect((await api(`/${body.id}/opens`)).status).toBe(200);
    const revoked = await api(`/${body.id}/revoke`, 'POST');
    expect(((await revoked.json()) as any).status).toBe('revoked');
  });

  it('enforces one active Free publication and Pro-only versions', async () => {
    const first = await api('/', 'POST', { ...input, sizeBytes: 100 });
    const { id } = (await first.json()) as { id: string };
    expect((await api('/', 'POST', { ...input, sizeBytes: 100 })).status).toBe(402);
    const version = await api(`/${id}/versions`, 'POST', { ...input, sizeBytes: 100 });
    expect(version.status).toBe(402);
    expect(await version.json()).toMatchObject({ upgradeUrl: expect.stringContaining('/pricing') });
  });

  it('allows a signed-in Pro owner to create a stable URL version 2', async () => {
    const ownerId = crypto.randomUUID();
    store.devices[0]!.userId = ownerId;
    store.entitlements.push({
      id: crypto.randomUUID(),
      userId: ownerId,
      source: 'paddle',
      externalId: 'sub_test',
      status: 'active',
      currentPeriodEnd: null,
    });
    const first = await api('/', 'POST', { ...input, sizeBytes: 100 });
    const body = (await first.json()) as { id: string; url: string };
    expect(store.publications[0]!.expiresAt).toBeNull();
    const updated = await api(`/${body.id}/versions`, 'POST', { ...input, sizeBytes: 100 });
    expect(updated.status).toBe(201);
    expect(await updated.json()).toMatchObject({ id: body.id, url: body.url, version: 2 });
  });

  it("counts only the Pro owner's ready versions toward storage quota", async () => {
    const ownerId = crypto.randomUUID();
    const otherId = crypto.randomUUID();
    store.devices[0]!.userId = ownerId;
    store.entitlements.push({
      id: crypto.randomUUID(),
      userId: ownerId,
      source: 'paddle',
      externalId: 'sub_owner',
      status: 'active',
      currentPeriodEnd: null,
    });
    const ownerPub = crypto.randomUUID();
    const otherPub = crypto.randomUUID();
    store.publications.push(
      { id: ownerPub, ownerUserId: ownerId, ownerDeviceId: store.devices[0]!.id, status: 'active' },
      { id: otherPub, ownerUserId: otherId, ownerDeviceId: crypto.randomUUID(), status: 'active' },
    );
    const cap = 2 * 1024 * 1024 * 1024;
    store.publicationVersions.push(
      {
        id: crypto.randomUUID(),
        publicationId: ownerPub,
        state: 'ready',
        totalBytes: cap - 100,
        number: 1,
      },
      {
        id: crypto.randomUUID(),
        publicationId: otherPub,
        state: 'ready',
        totalBytes: cap,
        number: 1,
      },
      {
        id: crypto.randomUUID(),
        publicationId: ownerPub,
        state: 'failed',
        totalBytes: cap,
        number: 2,
      },
    );
    const allowed = await api('/', 'POST', { ...input, sizeBytes: 50 });
    expect(allowed.status).toBe(201);
    const created = (await allowed.json()) as { id: string };
    expect((await api(`/${created.id}/versions`, 'POST', { ...input, sizeBytes: 50 })).status).toBe(
      201,
    );
    expect(
      (await api(`/${created.id}/versions`, 'POST', { ...input, sizeBytes: 101 })).status,
    ).toBe(413);
    expect((await api('/', 'POST', { ...input, sizeBytes: 101 })).status).toBe(413);
  });

  it('serves a Playwright report with assets relative to its HTML entry', async () => {
    const zip = zipSync({
      'reports/main.html': strToU8(
        '<html><head></head><body><script src="./assets/report.js"></script></body></html>',
      ),
      'reports/assets/report.js': strToU8('window.reportReady=true'),
    });
    const created = await api('/', 'POST', { ...input, sizeBytes: zip.length });
    const { id, url } = (await created.json()) as { id: string; url: string };
    objects.set(`pub/${id}/v1/_source`, zip);
    expect((await api(`/${id}/versions/1/complete`, 'POST')).status).toBe(200);
    const page = await worker.fetch(new Request(url), TEST_ENV, ctx);
    const html = await page.text();
    expect(html).toContain('<base href="/reports/">');
    expect(html).toContain('./assets/report.js');
    const asset = await worker.fetch(new Request(`${url}/reports/assets/report.js`), TEST_ENV, ctx);
    expect(await asset.text()).toBe('window.reportReady=true');
  });

  it('rejects incomplete uploads and invalid payloads', async () => {
    expect((await api('/', 'POST', { ...input, sizeBytes: -1 })).status).toBe(400);
    const first = await api('/', 'POST', { ...input, sizeBytes: 100 });
    const { id } = (await first.json()) as { id: string };
    expect((await api(`/${id}/versions/1/complete`, 'POST')).status).toBe(409);
    expect(store.publications).toHaveLength(1);
  });

  it('returns a problem+json unpack_error without publishing an invalid ZIP', async () => {
    const zip = zipSync({ '../index.html': strToU8('bad') });
    const first = await api('/', 'POST', { ...input, sizeBytes: zip.length });
    const { id } = (await first.json()) as { id: string };
    objects.set(`pub/${id}/v1/_source`, zip);
    const complete = await api(`/${id}/versions/1/complete`, 'POST');
    expect(complete.status).toBe(422);
    expect(complete.headers.get('content-type')).toContain('application/problem+json');
    expect(await complete.json()).toMatchObject({
      code: 'unpack_error',
      unpack_error: 'unsafe_path',
    });
    expect(store.publications[0]!.currentVersionId).toBeNull();
    expect(store.publicationVersions[0]!.state).toBe('failed');
    expect([...objects.keys()].filter((key) => key.startsWith(`pub/${id}/v1/`))).toEqual([]);
  });

  it('cleans the entire version prefix after a ZIP fails following an R2 write', async () => {
    const zip = zipSync({
      'index.html': strToU8('<html></html>'),
      'assets/app.js': strToU8('console.log(1)'),
    });
    const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength);
    let localHeaders = 0;
    for (let i = 0; i <= zip.length - 30; i++) {
      if (view.getUint32(i, true) !== 0x04034b50) continue;
      localHeaders++;
      if (localHeaders === 2) {
        view.setUint16(i + 8, 99, true);
        break;
      }
    }
    expect(localHeaders).toBe(2);
    const first = await api('/', 'POST', { ...input, sizeBytes: zip.length });
    const { id } = (await first.json()) as { id: string };
    const prefix = `pub/${id}/v1/`;
    objects.set(`${prefix}_source`, zip);
    objects.set(`${prefix}stale.txt`, strToU8('partial retry'));
    const complete = await api(`/${id}/versions/1/complete`, 'POST');
    expect(complete.status).toBe(422);
    expect(await complete.json()).toMatchObject({
      code: 'unpack_error',
      unpack_error: 'invalid_zip',
    });
    expect(writes).toContain(`${prefix}index.html`);
    expect([...objects.keys()].filter((key) => key.startsWith(prefix))).toEqual([]);
    expect(store.publicationVersions[0]!.state).toBe('failed');
    expect((await api(`/${id}/versions/1/complete`, 'POST')).status).toBe(409);
  });

  it('deduplicates the open beacon and returns a neutral 410 after expiry', async () => {
    const zip = zipSync({ 'index.html': strToU8('<html><head></head><body></body></html>') });
    const created = await api('/', 'POST', { ...input, sizeBytes: zip.length });
    const { id, url } = (await created.json()) as { id: string; url: string };
    objects.set(`pub/${id}/v1/_source`, zip);
    await api(`/${id}/versions/1/complete`, 'POST');
    const visitor = crypto.randomUUID();
    const same = () =>
      worker.fetch(
        new Request(`${url}/opened`, {
          method: 'POST',
          headers: { 'user-agent': 'Mozilla/5.0 Safari/605', 'content-type': 'application/json' },
          body: JSON.stringify({ visitor }),
        }),
        TEST_ENV,
        ctx,
      );
    expect((await same()).status).toBe(204);
    expect((await same()).status).toBe(204);
    expect(store.publicationOpens).toHaveLength(1);
    store.publications[0]!.expiresAt = new Date(0);
    await TEST_ENV.RATE_LIMIT.delete(`pub:cache:${store.publications[0]!.slug}`);
    const gone = await worker.fetch(new Request(url), TEST_ENV, ctx);
    expect(gone.status).toBe(410);
    expect(await gone.text()).not.toContain('index.html');
    expect(gone.headers.get('set-cookie') ?? '').not.toMatch(/Domain=\.fastsha\.red/i);
  });

  it('strips parent-domain cookies from every response surface', async () => {
    const sanitized = withoutDomainCookies(
      new Response('ok', { headers: { 'Set-Cookie': 'x=1; Domain=.fastsha.red; Path=/' } }),
    );
    expect(sanitized.headers.get('set-cookie')).toBeNull();
    expect(await sanitized.text()).toBe('ok');
  });
});
