import type { MiddlewareHandler } from 'hono';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { problem } from '~/lib/problem';
import { FREE_CAPS } from '~/lib/tierCaps';
import {
  findActiveProForDevice,
  isSubscriptionEntitled,
  parseAppleUserAllowList,
} from '~/services/subscriptions';
import { hmacSha256Hex } from '~/lib/hash';
import { log } from '~/lib/logger';

const UPGRADE_TARGET = { tier: 'pro' as const, url: 'https://fastsha.red/pricing' };
const FREE_TIER_MAX_SECONDS = FREE_CAPS.maxRetentionHours * 3600;
const UTC_DAY_SECONDS = 86_400;

// Free-tier enforcement. Runs AFTER auth() — requires `deviceId` in context.
// On Pro: returns immediately; caps live on the DB row, not KV.
// On Free: enforces the current Free caps from FREE_CAPS. During launch those
// caps are intentionally generous (unlimited daily uploads, 2 GB files,
// 30-day retention) while Cloud Sync remains Pro-only. If the caps are later
// tightened, retention policies above the cap are silently clamped instead of
// 4xxing the request.
//
// Body consumption is the big foot-gun here: Hono's `c.req.json()` consumes
// the underlying ReadableStream, so downstream Zod parsing would see an empty
// body. We clone the request, read once here, and **mutate** the context so
// downstream handlers read from the clamped copy.
export function rateLimitFreeTier(): MiddlewareHandler<AppBindings> {
  return async (c, next) => {
    const deviceId = c.get('deviceId');
    if (!deviceId) {
      return problem(c, 401, 'unauthorized', 'Unauthorized', 'no device on request');
    }

    const db = createDb(c.env.DATABASE_URL);
    const active = await findActiveProForDevice(
      db,
      deviceId,
      parseAppleUserAllowList(c.env.DEV_PRO_APPLE_USER_IDS, c.env.BETA_UNLIMITED_APPLE_USER_IDS),
    ).catch((err) => {
      log.warn({
        msg: 'free_tier_sub_lookup_failed',
        requestId: c.get('requestId'),
        error: err instanceof Error ? err.message : String(err),
      });
      return null;
    });
    const isPro = active !== null && isSubscriptionEntitled(active);
    if (isPro) {
      await next();
      return;
    }

    // Free path. Clone + parse once; if the body isn't JSON we let the
    // downstream Zod schema surface the error.
    const clone = c.req.raw.clone();
    let payload: Record<string, unknown>;
    try {
      payload = (await clone.json()) as Record<string, unknown>;
    } catch {
      await next();
      return;
    }

    // 1. Size cap — fail fast, no KV increment.
    const sizeBytes =
      typeof payload['sizeBytes'] === 'number' ? (payload['sizeBytes'] as number) : 0;
    const sizeLimitBytes = FREE_CAPS.maxFileSizeMB * 1024 * 1024;
    if (sizeBytes > sizeLimitBytes) {
      return problem(
        c,
        402,
        'free_tier_size_exceeded',
        'Payment Required',
        `Free tier is capped at ${FREE_CAPS.maxFileSizeMB} MB per upload.`,
        {
          limitMB: FREE_CAPS.maxFileSizeMB,
          actualMB: Math.ceil(sizeBytes / (1024 * 1024)),
          upgrade: UPGRADE_TARGET,
        },
      );
    }

    // 2. Retention clamp (silent). Rewrite the in-flight request so the
    //    downstream handler sees `oneDay` + no custom TTL.
    const retentionPolicy =
      typeof payload['retentionPolicy'] === 'string'
        ? (payload['retentionPolicy'] as string)
        : 'oneDay';
    const customTtl =
      typeof payload['customTtlSeconds'] === 'number'
        ? (payload['customTtlSeconds'] as number)
        : undefined;
    const effectiveTtl = ttlSecondsForPolicy(retentionPolicy, customTtl);
    const needsClamp = effectiveTtl === null || effectiveTtl > FREE_TIER_MAX_SECONDS;
    let bodyForDownstream: Record<string, unknown> = payload;
    if (needsClamp) {
      bodyForDownstream = {
        ...payload,
        retentionPolicy: 'oneDay',
      };
      // Strip the custom TTL — zod rejects customTtlSeconds when policy isn't
      // `custom`, and we've just switched to `oneDay`.
      delete (bodyForDownstream as Record<string, unknown>)['customTtlSeconds'];
      c.set('freeTierClampedRetention', true);
    }

    // 3. Daily-count cap. UTC-midnight key so the reset time is predictable
    //    across timezones. TTL is 2 days — one for the current window plus a
    //    safety margin for rollover.
    //
    // `-1` is the "unlimited" sentinel in TierCaps.uploadsPerDay. When the
    // tier has no daily cap we skip KV entirely so tests and logs don't show
    // phantom usage on the override path.
    if (FREE_CAPS.uploadsPerDay >= 0) {
      const utcDate = new Date().toISOString().slice(0, 10);
      const deviceKey = (await hmacSha256Hex(c.env.DEVICE_TOKEN_PEPPER, deviceId)).slice(0, 32);
      const kvKey = `ft:${deviceKey}:${utcDate}`;
      const currentStr = await c.env.RATE_LIMIT.get(kvKey);
      const currentCount = currentStr ? Number(currentStr) : 0;
      const safeCount = Number.isFinite(currentCount) ? currentCount : 0;
      if (safeCount >= FREE_CAPS.uploadsPerDay) {
        const resetsAt = nextUtcMidnight().toISOString();
        return problem(
          c,
          402,
          'free_tier_daily_exceeded',
          'Payment Required',
          `Free tier is capped at ${FREE_CAPS.uploadsPerDay} uploads per day.`,
          {
            limit: FREE_CAPS.uploadsPerDay,
            used: safeCount,
            resetsAt,
            upgrade: UPGRADE_TARGET,
          },
        );
      }
      await c.env.RATE_LIMIT.put(kvKey, String(safeCount + 1), {
        expirationTtl: 2 * UTC_DAY_SECONDS,
      });
    }

    // Replace the raw request with the clamped body so downstream Zod reads
    // the mutated version. We build a fresh Request because c.req.raw is
    // already drained after the original handler reads (we only read the
    // clone above, so the original body is still live — but Hono caches
    // parsed bodies, so we still want to override the JSON cache).
    if (needsClamp) {
      const clamped = new Request(c.req.raw.url, {
        method: c.req.raw.method,
        headers: c.req.raw.headers,
        body: JSON.stringify(bodyForDownstream),
      });
      c.req.raw = clamped;
      // Hono caches `.json()` results; clearing any cached value forces a
      // fresh parse downstream.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (c.req as any).bodyCache = {};
    }

    await next();
  };
}

function ttlSecondsForPolicy(policy: string, customTtlSeconds?: number): number | null {
  switch (policy) {
    case 'oneMinute':
      return 60;
    case 'oneHour':
      return 3600;
    case 'oneDay':
      return 86_400;
    case 'oneWeek':
      return 604_800;
    case 'oneMonth':
      return 2_592_000;
    case 'custom':
      return typeof customTtlSeconds === 'number' ? customTtlSeconds : null;
    default:
      return null;
  }
}

function nextUtcMidnight(now: Date = new Date()): Date {
  const d = new Date(now);
  d.setUTCHours(24, 0, 0, 0);
  return d;
}
