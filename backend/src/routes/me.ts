import { Hono } from 'hono';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { auth } from '~/middleware/auth';
import { ratelimit } from '~/middleware/ratelimit';
import { problem } from '~/lib/problem';
import { FREE_CAPS, PRO_CAPS, type TierCaps } from '~/lib/tierCaps';
import { findActiveByDeviceId } from '~/services/subscriptions';
import type { SubscriptionStatus } from '~/db/schema';

export const meRoutes = new Hono<AppBindings>();

meRoutes.use('/', auth());
meRoutes.use('/', ratelimit({ bucket: 'me', limit: 120, windowSeconds: 60 }));

interface MeResponse {
  tier: 'free' | 'monthly' | 'annual' | 'lifetime';
  expiresAt: string | null;
  caps: TierCaps;
  subscription: {
    status: SubscriptionStatus;
    autoRenewStatus: boolean;
  } | null;
}

meRoutes.get('/', async (c) => {
  const deviceId = c.get('deviceId');
  if (!deviceId) return problem(c, 401, 'unauthorized', 'Unauthorized', 'no device');

  const db = createDb(c.env.DATABASE_URL);
  const active = await findActiveByDeviceId(db, deviceId);

  // No active row at all → pure Free.
  if (!active) {
    const body: MeResponse = {
      tier: 'free',
      expiresAt: null,
      caps: FREE_CAPS,
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
      tier: 'free',
      expiresAt: null,
      caps: FREE_CAPS,
      subscription: null,
    };
    return c.json(body);
  }

  const body: MeResponse = {
    tier,
    expiresAt: active.expiresAt ? active.expiresAt.toISOString() : null,
    caps: PRO_CAPS,
    subscription: {
      status,
      autoRenewStatus: active.autoRenewStatus,
    },
  };
  return c.json(body);
});
