import { Hono } from 'hono';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { auth } from '~/middleware/auth';
import { ratelimit } from '~/middleware/ratelimit';
import { problem } from '~/lib/problem';
import { log } from '~/lib/logger';
import { PRO_CAPS, FREE_CAPS, toWireCaps, type TierCapsWire } from '~/lib/tierCaps';
import {
  AppStoreApiError,
  InvalidJwsError,
  createAppStoreServerApi,
  mapAppleStatusInt,
} from '~/lib/appStoreServerApi';
import {
  deriveStatusFromNotificationType,
  deriveTierFromProductId,
  findByOriginalTransactionId,
  isSubscriptionEntitled,
  upsertFromAppleEvent,
} from '~/services/subscriptions';
import type {
  Subscription,
  SubscriptionStatus,
  SubscriptionTier,
  SubscriptionVerificationStatus,
} from '~/db/schema';

export const iapRoutes = new Hono<AppBindings>();

// `POST /v1/iap/verify` is per-device authenticated: the client submits its
// StoreKit JWS `jwsRepresentation` and we resolve it to an authoritative
// subscription row. Ratelimit by device bucket (20 / 10 min).
//
// `POST /v1/iap/webhook` is PUBLIC — Apple posts notifications here and the
// signature on the JWS is the only trust anchor. We ratelimit by IP just to
// cap leaked-URL abuse; the signature check is what actually matters.
iapRoutes.use('/verify', auth());
iapRoutes.use('/verify', ratelimit({ bucket: 'iap_verify', limit: 20, windowSeconds: 600 }));
iapRoutes.use(
  '/webhook',
  ratelimit({ bucket: 'iap_webhook_ip', limit: 1000, windowSeconds: 60, keyFrom: 'ip' }),
);

const verifyBodySchema = z
  .object({
    jwsRepresentation: z.string().min(20).optional(),
    signedTransaction: z.string().min(20).optional(),
  })
  .refine((body) => body.jwsRepresentation || body.signedTransaction, {
    message: 'missing jwsRepresentation',
  });

const VERIFICATION_GRACE_MS = 24 * 60 * 60 * 1000;

iapRoutes.post('/verify', async (c) => {
  const deviceId = c.get('deviceId');
  if (!deviceId) return problem(c, 401, 'unauthorized', 'Unauthorized', 'no device');

  let parsed: z.infer<typeof verifyBodySchema>;
  try {
    parsed = verifyBodySchema.parse(await c.req.json());
  } catch {
    return problem(c, 400, 'bad_request', 'Bad Request', 'invalid body');
  }
  const jwsRepresentation = parsed.jwsRepresentation ?? parsed.signedTransaction;
  if (!jwsRepresentation) return problem(c, 400, 'bad_request', 'Bad Request', 'invalid body');

  const api = createAppStoreServerApi(c.env);

  // 1. Decode + verify the JWS signed transaction the client handed us.
  let decoded;
  try {
    decoded = await api.verifyTransactionJWS(jwsRepresentation);
  } catch (err) {
    const reason = err instanceof InvalidJwsError ? err.reason : 'unknown';
    log.warn({ msg: 'iap_verify_jws_invalid', requestId: c.get('requestId'), reason });
    return problem(c, 422, 'invalid_receipt', 'Unprocessable Entity', `invalid_jws:${reason}`);
  }

  // Sandbox-in-prod guard: sandbox receipts never unlock Pro in production.
  if (decoded.environment !== 'Production' && c.env.APP_ENV === 'production') {
    log.warn({
      msg: 'iap_verify_sandbox_in_prod',
      requestId: c.get('requestId'),
      originalTransactionId: decoded.originalTransactionId,
    });
    return problem(c, 422, 'invalid_receipt', 'Unprocessable Entity', 'sandbox_in_production');
  }

  if (decoded.bundleId !== c.env.APPLE_BUNDLE_ID) {
    return problem(c, 422, 'invalid_receipt', 'Unprocessable Entity', 'wrong_bundle');
  }

  // 2. Resolve product → tier. Unknown product IDs are a client bug (or a
  //    dev-run outside the registered catalog) — surface as 422.
  let tier;
  try {
    tier = deriveTierFromProductId(decoded.productId);
  } catch {
    return problem(c, 422, 'unknown_product', 'Unprocessable Entity', decoded.productId);
  }

  // 3. Ask Apple's Server API for the authoritative state (status int +
  //    autoRenewStatus). Lifetime products don't have a status lookup; fall
  //    back to `active` with no expiry.
  let status: SubscriptionStatus;
  let expiresAt: Date | null;
  let autoRenewStatus: boolean;
  let latestTransactionId = decoded.transactionId;
  let statusRaw: unknown = null;
  let verificationStatus: SubscriptionVerificationStatus = 'verified';
  let verificationGraceUntil: Date | null = null;

  if (tier === 'lifetime') {
    status = 'active';
    expiresAt = null;
    autoRenewStatus = false;
  } else {
    try {
      const statusResp = await api.getSubscriptionStatus(decoded.originalTransactionId);
      status = mapAppleStatusInt(statusResp.status);
      expiresAt = statusResp.expiresDate ?? decoded.expiresDate;
      autoRenewStatus = statusResp.autoRenewStatus;
      latestTransactionId = statusResp.latestTransactionId;
      statusRaw = statusResp.raw;
    } catch (err) {
      const now = Date.now();
      verificationStatus = 'grace';
      verificationGraceUntil = capGraceUntil(decoded.expiresDate, now);
      log.warn({
        msg: 'iap_verify_status_fetch_failed',
        requestId: c.get('requestId'),
        reason: err instanceof AppStoreApiError ? err.reason : 'unknown',
        graceUntil: verificationGraceUntil?.toISOString() ?? null,
      });
      status = 'active';
      expiresAt = decoded.expiresDate;
      autoRenewStatus = true;
    }
  }

  // 4. Upsert the row.
  const db = createDb(c.env.DATABASE_URL);
  const sub = await upsertFromAppleEvent(db, {
    deviceId,
    originalTransactionId: decoded.originalTransactionId,
    tier,
    status,
    expiresAt,
    autoRenewStatus,
    latestTransactionId,
    verificationStatus,
    verificationGraceUntil,
    rawNotificationPayload: {
      source: 'verify',
      apple: statusRaw,
    },
  });

  return c.json(iapEntitlementResponse(sub));
});

iapRoutes.post('/webhook', async (c) => {
  // SECURITY: verify Apple's JWS FIRST — before we parse the envelope, touch
  // the DB, or write to KV. A bad signature is 401 so Apple stops retrying.
  let bodyText: string;
  try {
    bodyText = await c.req.text();
  } catch {
    return problem(c, 400, 'bad_request', 'Bad Request', 'no body');
  }

  let signedPayload: string;
  try {
    const env = JSON.parse(bodyText) as { signedPayload?: unknown };
    if (typeof env.signedPayload !== 'string') {
      return problem(c, 400, 'bad_request', 'Bad Request', 'missing signedPayload');
    }
    signedPayload = env.signedPayload;
  } catch {
    return problem(c, 400, 'bad_request', 'Bad Request', 'invalid json');
  }

  const api = createAppStoreServerApi(c.env);

  let notification;
  try {
    notification = await api.verifyNotificationJWS(signedPayload);
  } catch (err) {
    const reason = err instanceof InvalidJwsError ? err.reason : 'unknown';
    log.warn({ msg: 'iap_webhook_jws_invalid', requestId: c.get('requestId'), reason });
    return problem(c, 401, 'unauthorized', 'Unauthorized', `invalid_jws:${reason}`);
  }

  // Idempotency: Apple retries on any non-2xx, and sometimes on 2xx. We de-dup
  // on notificationUUID. Seven-day TTL in KV matches Apple's documented retry
  // window.
  const idempotencyKey = `iap:notif:${notification.notificationUUID}`;
  const alreadySeen = await c.env.RATE_LIMIT.get(idempotencyKey);
  if (alreadySeen) {
    log.info({
      msg: 'iap_notif_duplicate',
      requestId: c.get('requestId'),
      notificationUUID: notification.notificationUUID,
      notificationType: notification.notificationType,
    });
    return c.json({ ok: true, duplicate: true });
  }

  if (notification.data.bundleId !== c.env.APPLE_BUNDLE_ID) {
    log.warn({
      msg: 'iap_webhook_wrong_bundle',
      requestId: c.get('requestId'),
      seen: notification.data.bundleId,
    });
    return c.json({ ok: true, ignored: 'wrong_bundle' });
  }

  if (notification.data.environment !== 'Production' && c.env.APP_ENV === 'production') {
    log.warn({
      msg: 'iap_webhook_sandbox_in_prod',
      requestId: c.get('requestId'),
      notificationType: notification.notificationType,
    });
    return c.json({ ok: true, ignored: 'sandbox_in_production' });
  }

  if (!notification.data.signedTransactionInfo) {
    log.warn({ msg: 'iap_webhook_no_transaction', requestId: c.get('requestId') });
    return c.json({ ok: true, ignored: 'no_transaction' });
  }

  let transaction;
  try {
    transaction = await api.verifyTransactionJWS(notification.data.signedTransactionInfo);
  } catch (err) {
    const reason = err instanceof InvalidJwsError ? err.reason : 'unknown';
    log.warn({ msg: 'iap_webhook_tx_invalid', requestId: c.get('requestId'), reason });
    return problem(c, 401, 'unauthorized', 'Unauthorized', `invalid_transaction:${reason}`);
  }

  let renewalAutoRenew: boolean | null = null;
  if (notification.data.signedRenewalInfo) {
    try {
      const renewal = await api.verifyRenewalInfoJWS(notification.data.signedRenewalInfo);
      renewalAutoRenew = renewal.autoRenewStatus;
    } catch {
      // Renewal info is advisory. Continue.
    }
  }

  const db = createDb(c.env.DATABASE_URL);
  const existing = await findByOriginalTransactionId(db, transaction.originalTransactionId);
  if (!existing) {
    // Orphan: no device linked yet (no /verify has landed for this sub). We
    // can't materialize a row without a deviceId. Persist the idempotency key
    // anyway so Apple doesn't retry.
    log.info({
      msg: 'iap_notif_orphan',
      requestId: c.get('requestId'),
      notificationUUID: notification.notificationUUID,
      notificationType: notification.notificationType,
    });
    await c.env.RATE_LIMIT.put(idempotencyKey, '1', { expirationTtl: 604_800 });
    return c.json({ ok: true, orphan: true });
  }

  // Compute the new status + tier.
  let tier;
  try {
    tier = deriveTierFromProductId(transaction.productId);
  } catch {
    log.warn({
      msg: 'iap_webhook_unknown_product',
      requestId: c.get('requestId'),
      productId: transaction.productId,
    });
    await c.env.RATE_LIMIT.put(idempotencyKey, '1', { expirationTtl: 604_800 });
    return c.json({ ok: true, ignored: 'unknown_product' });
  }

  let nextStatus: SubscriptionStatus;
  let nextAutoRenew: boolean;
  if (notification.notificationType === 'DID_CHANGE_RENEWAL_STATUS') {
    nextStatus = existing.status as SubscriptionStatus;
    nextAutoRenew = renewalAutoRenew ?? existing.autoRenewStatus;
  } else {
    const derived = deriveStatusFromNotificationType(
      notification.notificationType,
      notification.subtype ?? undefined,
    );
    nextStatus = derived === 'unchanged' ? (existing.status as SubscriptionStatus) : derived;
    nextAutoRenew = renewalAutoRenew ?? existing.autoRenewStatus;
  }

  await upsertFromAppleEvent(db, {
    deviceId: existing.deviceId,
    originalTransactionId: transaction.originalTransactionId,
    tier,
    status: nextStatus,
    expiresAt: transaction.expiresDate ?? existing.expiresAt,
    autoRenewStatus: nextAutoRenew,
    latestTransactionId: transaction.transactionId,
    verificationStatus: 'verified',
    verificationGraceUntil: null,
    rawNotificationPayload: {
      source: 'webhook',
      notificationUUID: notification.notificationUUID,
      notificationType: notification.notificationType,
      subtype: notification.subtype,
      decoded: {
        transaction: transaction.raw,
        renewal: renewalAutoRenew,
      },
    },
  });

  await c.env.RATE_LIMIT.put(idempotencyKey, '1', { expirationTtl: 604_800 });
  return c.json({ ok: true });
});

function capGraceUntil(expiresDate: Date | null, nowMs: number): Date {
  const defaultUntil = nowMs + VERIFICATION_GRACE_MS;
  if (!expiresDate) return new Date(defaultUntil);
  return new Date(Math.min(defaultUntil, expiresDate.getTime()));
}

interface IAPVerifyResponse {
  isPro: boolean;
  tier: 'free' | SubscriptionTier;
  expiresAt: string | null;
  caps: TierCapsWire;
  subscription: {
    status: SubscriptionStatus;
    autoRenewStatus: boolean;
    verificationStatus: SubscriptionVerificationStatus;
    verificationGraceUntil: string | null;
  } | null;
}

function iapEntitlementResponse(sub: Subscription, now = new Date()): IAPVerifyResponse {
  const entitled = isSubscriptionEntitled(sub, now);
  if (!entitled) {
    return {
      isPro: false,
      tier: 'free',
      expiresAt: null,
      caps: toWireCaps(FREE_CAPS),
      subscription: null,
    };
  }

  return {
    isPro: true,
    tier: sub.tier as SubscriptionTier,
    expiresAt: sub.expiresAt ? sub.expiresAt.toISOString() : null,
    caps: toWireCaps(PRO_CAPS),
    subscription: {
      status: sub.status as SubscriptionStatus,
      autoRenewStatus: sub.autoRenewStatus,
      verificationStatus: sub.verificationStatus as SubscriptionVerificationStatus,
      verificationGraceUntil: sub.verificationGraceUntil
        ? sub.verificationGraceUntil.toISOString()
        : null,
    },
  };
}
