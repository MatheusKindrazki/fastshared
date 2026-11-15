import { Hono } from 'hono';
import { and, eq, isNull, lte, or } from 'drizzle-orm';
import { z } from 'zod';
import type { AppBindings, Env } from '~/env';
import { createDb } from '~/db/client';
import { billingEvent, device, entitlement, user } from '~/db/schema';
import { auth } from '~/middleware/auth';
import { problem } from '~/lib/problem';
import { syncUserPublicationLifecycle } from '~/services/publicationLifecycle';

const eventSchema = z.object({
  event_id: z.string().min(1),
  event_type: z.string().min(1),
  occurred_at: z.string().datetime({ offset: true }),
  data: z
    .object({
      id: z.string().min(1),
      status: z.string().optional(),
      subscription_id: z.string().nullish(),
      customer_id: z.string().nullish(),
      custom_data: z.object({ userId: z.string().uuid().optional() }).passthrough().nullish(),
      current_billing_period: z
        .object({ ends_at: z.string().datetime({ offset: true }).nullish() })
        .nullish(),
    })
    .passthrough(),
});

type PaddleEvent = z.infer<typeof eventSchema>;
const handledEvents = new Set([
  'subscription.created',
  'subscription.updated',
  'subscription.activated',
  'subscription.canceled',
  'subscription.past_due',
  'transaction.completed',
]);

function hexBytes(hex: string): Uint8Array | null {
  if (!/^[a-fA-F0-9]{64}$/.test(hex)) return null;
  return Uint8Array.from(hex.match(/.{2}/g)!, (part) => parseInt(part, 16));
}

export async function verifyPaddleSignature(
  rawBody: string,
  header: string | undefined,
  secret: string | undefined,
  now = Date.now(),
): Promise<boolean> {
  if (!secret || !header) return false;
  const pieces = header.split(';').map((piece) => piece.trim().split('='));
  const ts = pieces.find((piece) => piece[0] === 'ts')?.[1];
  const candidates = pieces.filter((piece) => piece[0] === 'h1').map((piece) => piece[1]);
  if (!ts || !/^\d{10}$/.test(ts) || Math.abs(now - Number(ts) * 1000) > 300_000) return false;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const payload = new TextEncoder().encode(`${ts}:${rawBody}`);
  for (const candidate of candidates) {
    const signature = candidate ? hexBytes(candidate) : null;
    if (signature && (await crypto.subtle.verify('HMAC', key, signature as BufferSource, payload)))
      return true;
  }
  return false;
}

function eventStatus(event: PaddleEvent): 'active' | 'past_due' | 'canceled' | 'expired' | null {
  if (event.event_type === 'transaction.completed')
    return event.data.subscription_id ? 'active' : null;
  if (event.event_type === 'subscription.canceled') return 'canceled';
  if (event.event_type === 'subscription.past_due') return 'past_due';
  const status = event.data.status;
  if (status === 'active') return 'active';
  if (status === 'past_due') return 'past_due';
  if (status === 'canceled') return 'canceled';
  if (status === 'trialing' || status === 'paused') return 'expired';
  return event.event_type === 'subscription.activated' ? 'active' : null;
}

async function applyPaddleEvent(env: Env, event: PaddleEvent): Promise<void> {
  if (!handledEvents.has(event.event_type)) return;
  const subscriptionId =
    event.event_type === 'transaction.completed' ? event.data.subscription_id : event.data.id;
  const status = eventStatus(event);
  if (!subscriptionId || !status) return;
  const db = createDb(env.DATABASE_URL);
  const [existing] = await db
    .select()
    .from(entitlement)
    .where(and(eq(entitlement.source, 'paddle'), eq(entitlement.externalId, subscriptionId)))
    .limit(1);
  const userId = existing?.userId ?? event.data.custom_data?.userId;
  if (
    !userId ||
    (existing &&
      event.data.custom_data?.userId &&
      existing.userId !== event.data.custom_data.userId)
  ) {
    throw new Error('Paddle event has no consistent user');
  }
  const [owner] = await db.select().from(user).where(eq(user.id, userId)).limit(1);
  if (!owner) throw new Error('Paddle user not found');
  const occurredAt = new Date(event.occurred_at);
  if (existing?.lastEventAt && existing.lastEventAt > occurredAt) return;
  const customerId = event.data.customer_id ?? existing?.paddleCustomerId ?? null;
  const periodEnd = event.data.current_billing_period?.ends_at
    ? new Date(event.data.current_billing_period.ends_at)
    : (existing?.currentPeriodEnd ?? null);
  await db
    .insert(entitlement)
    .values({
      userId,
      source: 'paddle',
      externalId: subscriptionId,
      status,
      currentPeriodEnd: periodEnd,
      paddleCustomerId: customerId,
      lastEventAt: occurredAt,
    })
    .onConflictDoUpdate({
      target: [entitlement.source, entitlement.externalId],
      set: {
        status,
        currentPeriodEnd: periodEnd,
        paddleCustomerId: customerId,
        lastEventAt: occurredAt,
        updatedAt: new Date(),
      },
    setWhere: or(isNull(entitlement.lastEventAt), lte(entitlement.lastEventAt, occurredAt))!,
    });
  await syncUserPublicationLifecycle(env, userId);
}

export const billingRoutes = new Hono<AppBindings>();

billingRoutes.get('/config', (c) =>
  c.json({
    clientToken: c.env.PADDLE_CLIENT_TOKEN ?? '',
    environment: c.env.PADDLE_ENV ?? '',
    priceIds: {
      monthly: c.env.PADDLE_PRICE_MONTHLY ?? '',
      annual: c.env.PADDLE_PRICE_ANNUAL ?? '',
    },
  }),
);

billingRoutes.post('/paddle/webhook', async (c) => {
  const rawBody = await c.req.text();
  if (
    !(await verifyPaddleSignature(
      rawBody,
      c.req.header('Paddle-Signature'),
      c.env.PADDLE_WEBHOOK_SECRET,
    ))
  ) {
    return problem(c, 401, 'invalid_signature', 'Invalid Signature', 'Paddle signature invalid');
  }
  let body: unknown;
  try {
    body = JSON.parse(rawBody);
  } catch {
    body = null;
  }
  const parsed = eventSchema.safeParse(body);
  if (!parsed.success)
    return problem(c, 400, 'invalid_event', 'Invalid Event', 'Malformed Paddle event');
  const event = parsed.data;
  const db = createDb(c.env.DATABASE_URL);
  const [inserted] = await db
    .insert(billingEvent)
    .values({ eventId: event.event_id, eventType: event.event_type })
    .onConflictDoNothing({ target: billingEvent.eventId })
    .returning();
  if (!inserted) {
    const [previous] = await db
      .select()
      .from(billingEvent)
      .where(eq(billingEvent.eventId, event.event_id))
      .limit(1);
    if (previous?.status === 'processed') return c.json({ ok: true });
  }
  await applyPaddleEvent(c.env, event);
  await db
    .update(billingEvent)
    .set({ status: 'processed', processedAt: new Date() })
    .where(eq(billingEvent.eventId, event.event_id));
  return c.json({ ok: true });
});

billingRoutes.get('/portal', auth(), async (c) => {
  if (!c.env.PADDLE_API_KEY || !['sandbox', 'production'].includes(c.env.PADDLE_ENV ?? ''))
    return problem(
      c,
      503,
      'billing_unavailable',
      'Billing Unavailable',
      'Paddle API key is not configured',
    );
  const db = createDb(c.env.DATABASE_URL);
  const [ownerDevice] = await db
    .select()
    .from(device)
    .where(eq(device.id, c.get('deviceId')!))
    .limit(1);
  if (!ownerDevice?.userId)
    return problem(c, 403, 'account_required', 'Account Required', 'Sign in first');
  const rows = await db
    .select()
    .from(entitlement)
    .where(and(eq(entitlement.userId, ownerDevice.userId), eq(entitlement.source, 'paddle')));
  const customerId = rows.find((row) => row.paddleCustomerId)?.paddleCustomerId;
  if (!customerId)
    return problem(
      c,
      404,
      'billing_account_missing',
      'Billing Account Missing',
      'No Paddle customer is linked',
    );
  const base =
    c.env.PADDLE_ENV === 'sandbox' ? 'https://sandbox-api.paddle.com' : 'https://api.paddle.com';
  const response = await fetch(
    `${base}/customers/${encodeURIComponent(customerId)}/portal-sessions`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${c.env.PADDLE_API_KEY}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({}),
    },
  );
  if (!response.ok)
    return problem(
      c,
      502,
      'billing_portal_failed',
      'Billing Portal Failed',
      'Paddle portal unavailable',
    );
  const payload = (await response.json()) as {
    data?: { urls?: { general?: { overview?: string } } };
  };
  const url = payload.data?.urls?.general?.overview;
  if (!url)
    return problem(
      c,
      502,
      'billing_portal_failed',
      'Billing Portal Failed',
      'Paddle portal URL missing',
    );
  c.header('Cache-Control', 'no-store');
  return c.json({ url });
});
