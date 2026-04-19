import { describe, expect, it } from 'vitest';
import worker from '~/index';
import type { Env } from '~/env';

// Minimal env — this route does not touch DB, R2, or KV, but the worker's
// first-request env validator still runs so every required key must be set.
const TEST_ENV: Env = {
  DATABASE_URL: 'postgres://test',
  R2: {} as unknown as R2Bucket,
  RATE_LIMIT: {} as unknown as KVNamespace,
  R2_ACCOUNT_ID: 'acc',
  R2_ACCESS_KEY_ID: 'k',
  R2_SECRET_ACCESS_KEY: 's',
  R2_BUCKET_NAME: 'fastshared-test',
  SHORT_LINK_HOST: 'https://fsh.dev',
  PUBLIC_API_HOST: 'https://api.test.fastshared.app',
  DEVICE_TOKEN_PEPPER: 'test-pepper-test-pepper-test-pepper',
  APP_ENV: 'test',
};

const ctx: ExecutionContext = {
  waitUntil: () => undefined,
  passThroughOnException: () => undefined,
  props: {},
} as unknown as ExecutionContext;

async function fetchAASA(hostname: string): Promise<Response> {
  return worker.fetch(
    new Request(`https://${hostname}/.well-known/apple-app-site-association`, {
      headers: { accept: 'application/json' },
      redirect: 'manual',
    }),
    TEST_ENV,
    ctx,
  );
}

describe('apple-app-site-association', () => {
  // WHY: two separate assertions (fastsha.red + fsh.re) because iOS/macOS fetch
  // the AASA file per-hostname during install/update. If either returns HTML or
  // a wrong content-type the universal-link handoff silently never installs —
  // no runtime error, just a dead Share Sheet. Guard both.
  for (const host of ['fastsha.red', 'fsh.re'] as const) {
    it(`serves the manifest on ${host} with application/json`, async () => {
      const res = await fetchAASA(host);
      expect(res.status).toBe(200);
      expect(res.headers.get('content-type')).toMatch(/application\/json/);

      const body = await res.json();
      expect(body).toEqual({
        applinks: {
          apps: [],
          details: [
            {
              appID: 'YFYB6NKC73.dev.kindrazki.fastshared',
              paths: ['/s/*', 'NOT /api/*'],
            },
          ],
        },
      });
    });
  }

  // Pages-proxy sanity: the apex rewrites non-app paths to Cloudflare Pages
  // for the marketing site. /.well-known MUST stay on the worker so this
  // route is reachable on fastsha.red.
  it('is not proxied to Pages on the apex', async () => {
    const res = await fetchAASA('fastsha.red');
    expect(res.status).toBe(200);
    const body = (await res.json()) as { applinks?: unknown };
    expect(body.applinks).toBeDefined();
  });
});
