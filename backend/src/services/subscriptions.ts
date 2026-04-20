import { and, eq, ne, sql } from 'drizzle-orm';
import type { Db } from '~/db/client';
import {
  device,
  subscription,
  user,
  type Subscription,
  type SubscriptionStatus,
  type SubscriptionTier,
} from '~/db/schema';

// StoreKit product IDs. Keep in lockstep with the entries registered in App
// Store Connect AND with the client StoreKit configuration.
export const PRODUCT_ID_MONTHLY = 'red.fastsha.pro.monthly';
export const PRODUCT_ID_ANNUAL = 'red.fastsha.pro.annual';
export const PRODUCT_ID_LIFETIME = 'red.fastsha.pro.lifetime';

export async function findActiveByDeviceId(db: Db, deviceId: string): Promise<Subscription | null> {
  const rows = await db
    .select()
    .from(subscription)
    .where(and(eq(subscription.deviceId, deviceId), eq(subscription.status, 'active')))
    .limit(1);
  return rows[0] ?? null;
}

// Pro-override check for developer/internal accounts. Resolves the device's
// owning user and compares their Apple `sub` to the configured allow-list. If
// matched, fabricates an in-memory "active lifetime" subscription so every Pro
// gatekeeper (caps, rate limits, `/v1/me`) sees a single coherent answer
// without us having to poke rows into the real `subscription` table.
//
// Returns `null` on no match — callers should then fall back to the normal
// DB-backed `findActiveByDeviceId` path.
export async function findDevProOverride(
  db: Db,
  deviceId: string,
  allowedAppleUserIds: string[],
): Promise<Subscription | null> {
  if (allowedAppleUserIds.length === 0) return null;
  const rows = await db
    .select({ appleUserId: user.appleUserId })
    .from(device)
    .leftJoin(user, eq(device.userId, user.id))
    .where(eq(device.id, deviceId))
    .limit(1);
  const sub = rows[0]?.appleUserId;
  if (!sub || !allowedAppleUserIds.includes(sub)) return null;
  // Synthetic row — not persisted. IDs/timestamps are placeholders the
  // response layer stringifies but no other code branches on.
  const now = new Date();
  return {
    id: '00000000-0000-0000-0000-000000000000',
    deviceId,
    appleOriginalTransactionId: `dev-pro:${sub}`,
    tier: 'lifetime' as SubscriptionTier,
    status: 'active' as SubscriptionStatus,
    expiresAt: null,
    autoRenewStatus: false,
    latestTransactionId: `dev-pro:${sub}`,
    rawNotificationPayload: null,
    createdAt: now,
    updatedAt: now,
  } satisfies Subscription;
}

// Resolve the caller's effective Pro-bearing subscription. Checks the env
// allow-list first so dev/internal accounts are forever Pro without needing a
// real StoreKit transaction; falls back to the DB-backed lookup for everyone
// else. Single entry point for every gatekeeper in the codebase.
export async function findActiveProForDevice(
  db: Db,
  deviceId: string,
  devProAppleUserIds: string[] = [],
): Promise<Subscription | null> {
  const override = await findDevProOverride(db, deviceId, devProAppleUserIds);
  if (override) return override;
  return findActiveByDeviceId(db, deviceId);
}

// Parse the comma-separated env var into a deduped, trimmed list. Empty /
// missing → empty array so callers can pass directly without null-checking.
export function parseDevProAllowList(raw: string | undefined): string[] {
  if (!raw) return [];
  return [
    ...new Set(
      raw
        .split(',')
        .map((s) => s.trim())
        .filter((s) => s.length > 0),
    ),
  ];
}

export async function findByOriginalTransactionId(
  db: Db,
  originalTransactionId: string,
): Promise<Subscription | null> {
  const rows = await db
    .select()
    .from(subscription)
    .where(eq(subscription.appleOriginalTransactionId, originalTransactionId))
    .limit(1);
  return rows[0] ?? null;
}

export interface UpsertFromAppleEventArgs {
  deviceId: string;
  originalTransactionId: string;
  tier: SubscriptionTier;
  status: SubscriptionStatus;
  expiresAt: Date | null;
  autoRenewStatus: boolean;
  latestTransactionId: string;
  rawNotificationPayload: unknown;
}

export async function upsertFromAppleEvent(
  db: Db,
  args: UpsertFromAppleEventArgs,
): Promise<Subscription> {
  // If we're about to flip a DIFFERENT subscription to active for the same
  // device, expire any currently-active sibling rows first so the partial
  // unique index on (device_id) WHERE status = 'active' doesn't reject us.
  // Neon HTTP doesn't expose transactions, so we run the two statements
  // sequentially; the worst case is a brief window with zero active rows,
  // not two — and the follow-up upsert will re-establish the invariant.
  if (args.status === 'active') {
    await db
      .update(subscription)
      .set({ status: 'expired', updatedAt: sql`now()` })
      .where(
        and(
          eq(subscription.deviceId, args.deviceId),
          eq(subscription.status, 'active'),
          ne(subscription.appleOriginalTransactionId, args.originalTransactionId),
        ),
      );
  }

  const values = {
    deviceId: args.deviceId,
    appleOriginalTransactionId: args.originalTransactionId,
    tier: args.tier,
    status: args.status,
    expiresAt: args.expiresAt,
    autoRenewStatus: args.autoRenewStatus,
    latestTransactionId: args.latestTransactionId,
    rawNotificationPayload: args.rawNotificationPayload,
  };

  const [row] = await db
    .insert(subscription)
    .values(values)
    .onConflictDoUpdate({
      target: subscription.appleOriginalTransactionId,
      set: {
        tier: args.tier,
        status: args.status,
        expiresAt: args.expiresAt,
        autoRenewStatus: args.autoRenewStatus,
        latestTransactionId: args.latestTransactionId,
        rawNotificationPayload: args.rawNotificationPayload,
        updatedAt: sql`now()`,
      },
    })
    .returning();

  if (!row) throw new Error('subscription upsert returned no rows');
  return row;
}

// Pure map of product ID → tier. Unknown → throw (route turns that into 422).
export function deriveTierFromProductId(productId: string): SubscriptionTier {
  switch (productId) {
    case PRODUCT_ID_MONTHLY:
      return 'monthly';
    case PRODUCT_ID_ANNUAL:
      return 'annual';
    case PRODUCT_ID_LIFETIME:
      return 'lifetime';
    default:
      throw new Error(`unknown product id: ${productId}`);
  }
}

// Apple App Store Server Notifications v2 notification types → our status.
// Reference: https://developer.apple.com/documentation/appstoreservernotifications/notificationtype
// The `unchanged` sentinel tells the caller "don't touch status, only flip
// auto_renew_status". Exported for tests + IAP webhook dispatch.
export type DerivedStatus = SubscriptionStatus | 'unchanged';

export function deriveStatusFromNotificationType(
  notificationType: string,
  subtype?: string,
): DerivedStatus {
  switch (notificationType) {
    case 'DID_RENEW':
      return 'active';
    case 'EXPIRED':
      return 'expired';
    case 'REFUND':
      return 'refunded';
    case 'REVOKE':
      return 'revoked';
    case 'GRACE_PERIOD_EXPIRED':
      return 'expired';
    case 'DID_CHANGE_RENEWAL_STATUS':
      return 'unchanged';
    case 'DID_FAIL_TO_RENEW':
      // With `GRACE_PERIOD` subtype Apple is giving the user a grace window
      // — still entitled to Pro. Otherwise we're in billing retry.
      return subtype === 'GRACE_PERIOD' ? 'in_grace' : 'in_billing_retry';
    case 'SUBSCRIBED':
    case 'DID_CHANGE_RENEWAL_PREF':
      return 'active';
    case 'PRICE_INCREASE':
    case 'CONSUMPTION_REQUEST':
    case 'RENEWAL_EXTENDED':
    case 'RENEWAL_EXTENSION':
    case 'TEST':
    case 'OFFER_REDEEMED':
      return 'unchanged';
    default:
      return 'unchanged';
  }
}
