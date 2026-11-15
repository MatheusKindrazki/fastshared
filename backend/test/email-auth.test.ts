import { beforeEach, describe, expect, it, vi } from 'vitest';
import { installDrizzleFake, resetKv, resetStore, store, TEST_ENV, ctx } from './support';

installDrizzleFake();
const sent = vi.hoisted(() => [] as string[]);
const senderState = vi.hoisted(() => ({ fail: false }));
vi.mock('~/services/emailSender', () => ({
  emailSender: () => ({
    sendMagicLink: async (_to: string, url: string) => {
      if (senderState.fail) throw new Error('sender failed');
      sent.push(url);
    },
  }),
}));

import worker from '~/index';

async function start(email: string, ip = '203.0.113.1') {
  return worker.fetch(
    new Request('https://api.fastsha.red/v1/auth/email/start', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': ip },
      body: JSON.stringify({ email }),
    }),
    TEST_ENV,
    ctx,
  );
}

async function openLink(url: string) {
  return worker.fetch(new Request(url), TEST_ENV, ctx);
}

async function continueSignIn(url: string) {
  const token = new URL(url).searchParams.get('token')!;
  return worker.fetch(
    new Request('https://api.fastsha.red/v1/auth/email/verify', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ token }),
    }),
    TEST_ENV,
    ctx,
  );
}

beforeEach(() => {
  resetStore();
  resetKv();
  sent.length = 0;
  senderState.fail = false;
  TEST_ENV.WEB_APP_ORIGIN = 'https://fastsha.red';
});

describe('email magic link', () => {
  it('returns the same 202 for valid, invalid and rate-limited starts', async () => {
    expect((await start('buyer@example.com')).status).toBe(202);
    expect((await start('invalid')).status).toBe(202);
    for (let i = 0; i < 8; i++) expect((await start('buyer@example.com')).status).toBe(202);
    expect(sent).toHaveLength(5);
  });

  it('limits the source IP even when addresses vary', async () => {
    for (let i = 0; i < 12; i++) expect((await start(`buyer${i}@example.com`)).status).toBe(202);
    expect(sent).toHaveLength(10);
  });

  it('keeps 202 when the sender fails', async () => {
    senderState.fail = true;
    expect((await start('buyer@example.com')).status).toBe(202);
    expect(sent).toHaveLength(0);
  });

  it('GET shows a restricted confirmation page without consuming the token', async () => {
    await start('buyer@example.com');
    const page = await openLink(sent[0]!);
    expect(page.status).toBe(200);
    const html = await page.text();
    expect(html).toContain('Continue to FastShared');
    expect(html).not.toMatch(/<script|\bsrc=/i);
    expect(page.headers.get('content-security-policy')).toContain("form-action 'self'");
    expect(page.headers.get('content-security-policy')).toContain("default-src 'none'");
    expect(page.headers.get('x-robots-tag')).toContain('noindex');
    expect(page.headers.get('cache-control')).toBe('no-store');
    expect(store.emailLoginTokens[0]?.consumedAt).toBeNull();
    expect(store.users).toHaveLength(0);
    expect((await openLink(sent[0]!)).status).toBe(200);
    expect(store.emailLoginTokens[0]?.consumedAt).toBeNull();
  });

  it('POST consumes the token once and redirects with a web bearer in the fragment', async () => {
    await start('Buyer@Example.com');
    await openLink(sent[0]!);
    const first = await continueSignIn(sent[0]!);
    expect(first.status).toBe(302);
    expect(first.headers.get('location')).toMatch(/^https:\/\/fastsha\.red\/account#token=/);
    expect(first.headers.get('cache-control')).toBe('no-store');
    expect(store.users[0]?.email).toBe('buyer@example.com');
    expect(store.devices[0]?.platform).toBe('web');
    expect(store.devices[0]?.userId).toBe(store.users[0]?.id);
    expect(store.emailLoginTokens[0]?.consumedAt).toBeInstanceOf(Date);
    expect((await continueSignIn(sent[0]!)).status).toBe(400);
    expect(store.devices).toHaveLength(1);
  });

  it('rejects expired links without creating a user', async () => {
    await start('buyer@example.com');
    store.emailLoginTokens[0]!.expiresAt = new Date(Date.now() - 1000);
    expect((await openLink(sent[0]!)).status).toBe(200);
    expect((await continueSignIn(sent[0]!)).status).toBe(400);
    expect(store.users).toHaveLength(0);
  });
});
