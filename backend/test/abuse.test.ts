import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ctx, installDrizzleFake, resetKv, resetStore, store, TEST_ENV } from './support';

installDrizzleFake();
import worker from '~/index';

const token = 'abuseTokenAAAAAAAAAAAA';

async function post(path: string, body?: unknown, authorization?: string): Promise<Response> {
  return worker.fetch(
    new Request(`https://api.fastsha.red${path}`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'cf-connecting-ip': '203.0.113.4',
        ...(authorization ? { authorization } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    }),
    TEST_ENV,
    ctx,
  );
}

describe('abuse reports and admin takedown', () => {
  beforeEach(() => {
    resetStore();
    resetKv();
    delete TEST_ENV.ADMIN_TOKEN;
    TEST_ENV.USER_CONTENT_HOST = '';
    vi.spyOn(console, 'log').mockImplementation(() => {});
    store.shareLinks.push({
      id: crypto.randomUUID(),
      token,
      assetId: crypto.randomUUID(),
      visibility: 'signed',
      expiresAt: new Date(Date.now() + 3600_000),
      hits: 0,
      linkStatus: 'active',
      retentionPolicy: 'oneDay',
      revokedAt: null,
      lastAccessedAt: null,
      accessCount: 0,
      maxAccessCount: null,
      createdAt: new Date(),
    });
  });

  it('persists an anonymous report and rate limits repeated requests', async () => {
    for (let i = 0; i < 5; i++) {
      const res = await post('/v1/abuse-reports', { token, reason: 'phishing' });
      expect(res.status).toBe(201);
    }
    expect(store.abuseReports).toHaveLength(5);
    expect(store.abuseReports[0]).toMatchObject({
      shareLinkId: store.shareLinks[0]!.id,
      reason: 'phishing',
    });
    expect(store.shareLinks[0]!.linkStatus).toBe('active');
    const limited = await post('/v1/abuse-reports', { token, reason: 'phishing' });
    expect(limited.status).toBe(429);
    expect(limited.headers.get('Retry-After')).not.toBeNull();
    expect(store.abuseReports).toHaveLength(5);
  });

  it('requires the configured admin secret before revoking a reported link', async () => {
    const received = await post('/v1/abuse-reports', { token, reason: 'malware' });
    const { id } = (await received.json()) as { id: string };
    const path = `/v1/abuse-reports/${id}/revoke`;
    expect((await post(path)).status).toBe(503);
    TEST_ENV.ADMIN_TOKEN = 'test-admin-secret';
    expect((await post(path)).status).toBe(401);
    expect((await post(path, undefined, 'Bearer wrong')).status).toBe(401);
    expect(store.shareLinks[0]!.linkStatus).toBe('active');
    const revoked = await post(path, undefined, 'Bearer test-admin-secret');
    expect(revoked.status).toBe(200);
    expect(store.shareLinks[0]!.linkStatus).toBe('revoked');
    expect(store.abuseReports[0]!.resolvedAt).toBeInstanceOf(Date);
    const after = await worker.fetch(
      new Request(`https://fastsha.red/s/${token}/raw`),
      TEST_ENV,
      ctx,
    );
    expect(after.status).toBe(410);
  });
});
