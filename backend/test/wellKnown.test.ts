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
  SHORT_LINK_HOST: 'https://fastsha.red',
  PUBLIC_API_HOST: 'https://api.fastsha.red',
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
  // fastsha.red is the only production hostname — the apex serves both the
  // marketing site (proxied to Pages) and the short-link resolver (/s/*),
  // and iOS/macOS fetch the AASA file from it during install/update. If the
  // file returns HTML or a wrong content-type the universal-link handoff
  // silently never installs — no runtime error, just a dead Share Sheet.
  it('serves the manifest on fastsha.red with application/json', async () => {
    const res = await fetchAASA('fastsha.red');
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
