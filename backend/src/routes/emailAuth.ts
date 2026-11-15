import { Hono, type Context } from 'hono';
import { and, eq, gt, isNull } from 'drizzle-orm';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { device, emailLoginToken, user } from '~/db/schema';
import { hmacSha256Hex, toBase64Url } from '~/lib/hash';
import { log } from '~/lib/logger';
import { problem } from '~/lib/problem';
import { emailSender } from '~/services/emailSender';

const emailSchema = z.object({ email: z.string().email().max(256) });
const WINDOW = 900;

export const emailAuthRoutes = new Hono<AppBindings>();

async function withinLimit(c: Context<AppBindings>, email: string): Promise<boolean> {
  const now = Math.floor(Date.now() / 1000);
  const window = now - (now % WINDOW);
  const ip = c.req.header('cf-connecting-ip') ?? 'unknown';
  const keys = await Promise.all(
    [`ip:${ip}`, `email:${email}`].map(
      async (identity) =>
        `rl:email:${(await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, identity)).slice(0, 32)}:${window}`,
    ),
  );
  const limits = [10, 5];
  const counts = await Promise.all(keys.map((key) => c.env.RATE_LIMIT.get(key)));
  if (counts.some((value, index) => Number(value ?? 0) >= limits[index]!)) return false;
  await Promise.all(
    keys.map((key, index) =>
      c.env.RATE_LIMIT.put(key, String(Number(counts[index] ?? 0) + 1), {
        expirationTtl: WINDOW + 60,
      }),
    ),
  );
  return true;
}

emailAuthRoutes.post('/start', async (c) => {
  const accepted = () => c.body(null, 202, { 'Cache-Control': 'no-store' });
  const parsed = emailSchema.safeParse(await c.req.json().catch(() => null));
  if (!parsed.success) return accepted();
  try {
    const email = parsed.data.email.trim().toLowerCase();
    if (!(await withinLimit(c, email))) return accepted();
    const sender = emailSender(c.env);
    if (!sender || !c.env.WEB_APP_ORIGIN) {
      log.warn({ msg: 'email_auth_not_configured', requestId: c.get('requestId') });
      return accepted();
    }
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    const token = toBase64Url(bytes);
    const tokenHash = await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, token);
    const db = createDb(c.env.DATABASE_URL);
    await db.insert(emailLoginToken).values({
      tokenHash,
      email,
      expiresAt: new Date(Date.now() + WINDOW * 1000),
    });
    const url = new URL('/v1/auth/email/verify', c.env.PUBLIC_API_HOST);
    url.searchParams.set('token', token);
    await sender.sendMagicLink(email, url.toString());
  } catch (err) {
    log.warn({
      msg: 'email_auth_send_failed',
      requestId: c.get('requestId'),
      error: err instanceof Error ? err.message : String(err),
    });
  }
  return accepted();
});

emailAuthRoutes.get('/verify', async (c) => {
  const token = c.req.query('token');
  if (!token || !/^[A-Za-z0-9_-]{43}$/.test(token) || !c.env.WEB_APP_ORIGIN) {
    return problem(c, 400, 'invalid_link', 'Invalid Link', 'Invalid or expired sign-in link');
  }
  const response = c.html(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>Sign in to FastShared</title>
</head>
<body>
  <main>
    <h1>Sign in to FastShared</h1>
    <form method="post" action="/v1/auth/email/verify">
      <input type="hidden" name="token" value="${token}">
      <button type="submit">Continue to FastShared</button>
    </form>
  </main>
</body>
</html>`);
  response.headers.set('Cache-Control', 'no-store');
  response.headers.set('Referrer-Policy', 'no-referrer');
  response.headers.set('X-Robots-Tag', 'noindex, nofollow');
  response.headers.set(
    'Content-Security-Policy',
    "default-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
  );
  return response;
});

emailAuthRoutes.post('/verify', async (c) => {
  const form = await c.req.formData().catch(() => null);
  const token = form?.get('token');
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(token) || !c.env.WEB_APP_ORIGIN) {
    return problem(c, 400, 'invalid_link', 'Invalid Link', 'Invalid or expired sign-in link');
  }
  const db = createDb(c.env.DATABASE_URL);
  const tokenHash = await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, token);
  const [claim] = await db
    .update(emailLoginToken)
    .set({ consumedAt: new Date() })
    .where(
      and(
        eq(emailLoginToken.tokenHash, tokenHash),
        isNull(emailLoginToken.consumedAt),
        gt(emailLoginToken.expiresAt, new Date()),
      ),
    )
    .returning();
  if (!claim)
    return problem(c, 400, 'invalid_link', 'Invalid Link', 'Invalid or expired sign-in link');

  await db.insert(user).values({ email: claim.email }).onConflictDoNothing({ target: user.email });
  const [owner] = await db.select().from(user).where(eq(user.email, claim.email)).limit(1);
  if (!owner) throw new Error('email user lookup failed');
  const deviceToken = toBase64Url(crypto.getRandomValues(new Uint8Array(32)));
  await db.insert(device).values({
    tokenHash: await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, deviceToken),
    platform: 'web',
    appVersion: 'web',
    userId: owner.id,
  });
  const target = new URL('/account', c.env.WEB_APP_ORIGIN);
  target.hash = `token=${deviceToken}`;
  const response = c.redirect(target.toString(), 302);
  response.headers.set('Cache-Control', 'no-store');
  response.headers.set('Referrer-Policy', 'no-referrer');
  return response;
});
