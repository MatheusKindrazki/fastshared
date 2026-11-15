import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ctx, installDrizzleFake, resetKv, resetStore, store, TEST_ENV } from './support';

installDrizzleFake();
import worker from '~/index';

const token = 'abuseTokenAAAAAAAAAAAA';

async function post(
  path: string,
  body?: unknown,
  authorization?: string,
  ip = '203.0.113.4',
): Promise<Response> {
  return worker.fetch(
    new Request(`https://api.fastsha.red${path}`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'cf-connecting-ip': ip,
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

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('persists an anonymous report and rate limits repeated requests', async () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    for (let i = 0; i < 5; i++) {
      const res = await post('/v1/abuse-reports', { token, reason: 'phishing' });
      expect(res.status).toBe(201);
    }
    expect(store.abuseReports).toHaveLength(5);
    expect(store.abuseReports[0]).toMatchObject({
      shareLinkId: store.shareLinks[0]!.id,
      reason: 'phishing',
    });
    expect(store.abuseReports[0]!.ipHash).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(store.abuseReports)).not.toContain('203.0.113.4');
    const receivedLog = logSpy.mock.calls
      .map(([line]) => String(line))
      .find((line) => line.includes('"msg":"abuse_report_received"'));
    expect(JSON.parse(receivedLog!)).toMatchObject({
      msg: 'abuse_report_received',
      token,
      reason: 'phishing',
    });
    expect(receivedLog).not.toContain('203.0.113.4');
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
    expect(store.deletionJobs).toContainEqual(
      expect.objectContaining({ assetId: store.shareLinks[0]!.assetId, status: 'pending' }),
    );
    expect(store.abuseReports[0]!.resolvedAt).toBeInstanceOf(Date);
    const after = await worker.fetch(
      new Request(`https://fastsha.red/s/${token}/raw`),
      TEST_ENV,
      ctx,
    );
    expect(after.status).toBe(410);
  });

  it('revokes after three distinct reporter IPs within 24 hours', async () => {
    const body = { token, reason: 'phishing' };
    expect((await post('/v1/abuse-reports', body, undefined, '203.0.113.1')).status).toBe(201);
    store.abuseReports[0]!.createdAt = new Date(Date.now() - 25 * 60 * 60 * 1000);
    expect((await post('/v1/abuse-reports', body, undefined, '203.0.113.2')).status).toBe(201);
    expect((await post('/v1/abuse-reports', body, undefined, '203.0.113.3')).status).toBe(201);
    expect(store.shareLinks[0]!.linkStatus).toBe('active');
    expect((await post('/v1/abuse-reports', body, undefined, '203.0.113.4')).status).toBe(201);
    expect(store.shareLinks[0]!.linkStatus).toBe('revoked');
    expect(store.deletionJobs).toContainEqual(
      expect.objectContaining({ assetId: store.shareLinks[0]!.assetId, status: 'pending' }),
    );
    const after = await worker.fetch(
      new Request(`https://fastsha.red/s/${token}/raw`),
      TEST_ENV,
      ctx,
    );
    expect(after.status).toBe(410);
  });

  it('counts reports separately for each link', async () => {
    const otherToken = 'otherAbuseTokenAAAAAAAA';
    store.shareLinks.push({
      ...store.shareLinks[0]!,
      id: crypto.randomUUID(),
      token: otherToken,
      assetId: crypto.randomUUID(),
    });
    expect(
      (await post('/v1/abuse-reports', { token, reason: 'spam' }, undefined, '203.0.113.1')).status,
    ).toBe(201);
    expect(
      (
        await post(
          '/v1/abuse-reports',
          { token: otherToken, reason: 'spam' },
          undefined,
          '203.0.113.2',
        )
      ).status,
    ).toBe(201);
    expect(
      (
        await post(
          '/v1/abuse-reports',
          { token: otherToken, reason: 'spam' },
          undefined,
          '203.0.113.3',
        )
      ).status,
    ).toBe(201);
    expect(store.shareLinks.every((link) => link.linkStatus === 'active')).toBe(true);
  });
});
