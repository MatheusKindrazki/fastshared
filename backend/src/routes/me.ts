import { Hono } from 'hono';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { auth } from '~/middleware/auth';
import { ratelimit } from '~/middleware/ratelimit';
import { problem } from '~/lib/problem';
import { FREE_CAPS, PRO_CAPS, toWireCaps, type TierCapsWire } from '~/lib/tierCaps';
import { findActiveProForDevice, parseDevProAllowList } from '~/services/subscriptions';
import type { SubscriptionStatus } from '~/db/schema';

export const meRoutes = new Hono<AppBindings>();

meRoutes.use('/', auth());
meRoutes.use('/', ratelimit({ bucket: 'me', limit: 120, windowSeconds: 60 }));

// WHY: `caps` uses the client-wire shape (TierCapsWire) rather than the
// internal TierCaps — iOS `TierCapsDTO` decodes
// `{dailyUploadLimit, maxFileSizeBytes, maxRetentionSeconds, allowsCloudSync}`.
// Serving the internal shape caused silent decode failures, leaving the app
// pinned to its hardcoded default caps no matter what the server reported.
// `isPro` is duplicated at the top level because the client keys its paywall
// gate on `MeResponse.isPro`, not on `tier` alone.
interface MeResponse {
  isPro: boolean;
  tier: 'free' | 'monthly' | 'annual' | 'lifetime';
  expiresAt: string | null;
  caps: TierCapsWire;
  subscription: {
    status: SubscriptionStatus;
    autoRenewStatus: boolean;
  } | null;
}

meRoutes.get('/', async (c) => {
  const deviceId = c.get('deviceId');
  if (!deviceId) return problem(c, 401, 'unauthorized', 'Unauthorized', 'no device');

  const db = createDb(c.env.DATABASE_URL);
  const active = await findActiveProForDevice(
    db,
    deviceId,
    parseDevProAllowList(c.env.DEV_PRO_APPLE_USER_IDS),
  );

  // No active row at all → pure Free.
  if (!active) {
    const body: MeResponse = {
      isPro: false,
      tier: 'free',
      expiresAt: null,
      caps: toWireCaps(FREE_CAPS),
      subscription: null,
    };
    return c.json(body);
  }

  const status = active.status as SubscriptionStatus;
  const tier = active.tier as MeResponse['tier'];

  // Grace / billing-retry: Apple's documented position is that the user is
  // still entitled to Pro during these windows. Map to PRO_CAPS.
  // expired/revoked/refunded → downgrade to Free in the response. Those rows
  // shouldn't normally be returned by findActiveByDeviceId (it filters on
  // status='active') but we defense-in-depth just in case.
  const proStatuses: SubscriptionStatus[] = ['active', 'in_grace', 'in_billing_retry'];
  const isPro = proStatuses.includes(status);
  if (!isPro) {
    const body: MeResponse = {
      isPro: false,
      tier: 'free',
      expiresAt: null,
      caps: toWireCaps(FREE_CAPS),
      subscription: null,
    };
    return c.json(body);
  }

  const body: MeResponse = {
    isPro: true,
    tier,
    expiresAt: active.expiresAt ? active.expiresAt.toISOString() : null,
    caps: toWireCaps(PRO_CAPS),
    subscription: {
      status,
      autoRenewStatus: active.autoRenewStatus,
    },
  };
  return c.json(body);
});
