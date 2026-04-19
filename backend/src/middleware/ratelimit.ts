import type { MiddlewareHandler } from 'hono';
import type { AppBindings } from '~/env';
import { problem } from '~/lib/problem';

export interface RatelimitOptions {
  bucket: string;
  limit: number;
  windowSeconds: number;
  // Key selector: default prefers deviceId, else client IP.
  keyFrom?: 'device' | 'ip';
}

// Fixed-window counter in KV. Good enough for MVP; a Durable Object counter is
// the correctness upgrade (atomic increment + strong consistency).
export const ratelimit = (opts: RatelimitOptions): MiddlewareHandler<AppBindings> => {
  const { bucket, limit, windowSeconds } = opts;
  return async (c, next) => {
    const keyFrom = opts.keyFrom ?? 'device';
    const identity =
      keyFrom === 'device'
        ? (c.get('deviceId') ?? anonKey(c.req.header('cf-connecting-ip')))
        : anonKey(c.req.header('cf-connecting-ip'));

    const now = Math.floor(Date.now() / 1000);
    const windowStart = now - (now % windowSeconds);
    const key = `rl:${identity}:${bucket}:${windowStart}`;
    const ttl = windowSeconds + 60;

    const existing = await c.env.RATE_LIMIT.get(key);
    const current = existing ? Number(existing) : 0;
    if (!Number.isFinite(current)) {
      // Defensive: treat corrupt values as zero rather than locking out users.
      await c.env.RATE_LIMIT.put(key, '1', { expirationTtl: ttl });
    } else if (current >= limit) {
      const retryAfter = windowStart + windowSeconds - now;
      const res = problem(
        c,
        429,
        'rate_limited',
        'Too Many Requests',
        `Limit of ${limit} per ${windowSeconds}s exceeded for bucket '${bucket}'`,
      );
      res.headers.set('Retry-After', String(Math.max(retryAfter, 1)));
      return res;
    } else {
      await c.env.RATE_LIMIT.put(key, String(current + 1), { expirationTtl: ttl });
    }
    await next();
  };
};

function anonKey(ip: string | undefined): string {
  return `ip:${ip ?? 'unknown'}`;
}
