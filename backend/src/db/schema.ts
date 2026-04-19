import { sql } from 'drizzle-orm';
import {
  bigint,
  boolean,
  customType,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';
import type { InferInsertModel, InferSelectModel } from 'drizzle-orm';

const citext = customType<{ data: string }>({
  dataType() {
    return 'citext';
  },
});

export const user = pgTable('user', {
  id: uuid('id')
    .primaryKey()
    .default(sql`gen_random_uuid()`),
  email: citext('email').unique(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

export const device = pgTable('device', {
  id: uuid('id')
    .primaryKey()
    .default(sql`gen_random_uuid()`),
  tokenHash: text('token_hash').notNull().unique(),
  platform: text('platform').notNull(),
  appVersion: text('app_version').notNull(),
  userId: uuid('user_id').references(() => user.id),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).notNull().defaultNow(),
});

// Allowed values for asset.deletion_status, enforced via CHECK in SQL migration.
export const ASSET_DELETION_STATUSES = ['pending', 'scheduled', 'deleted', 'failed'] as const;
export type AssetDeletionStatus = (typeof ASSET_DELETION_STATUSES)[number];

export const asset = pgTable(
  'asset',
  {
    id: uuid('id')
      .primaryKey()
      .default(sql`gen_random_uuid()`),
    ownerDeviceId: uuid('owner_device_id')
      .notNull()
      .references(() => device.id),
    ownerUserId: uuid('owner_user_id').references(() => user.id),
    bucket: text('bucket').notNull(),
    storageKey: text('storage_key').notNull().unique(),
    contentType: text('content_type').notNull(),
    sizeBytes: bigint('size_bytes', { mode: 'number' }).notNull(),
    sha256: text('sha256'),
    originalFilename: text('original_filename'),
    // status: 'pending' | 'verified' | 'failed' | 'deleted' (CHECK in SQL).
    status: text('status').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    verifiedAt: timestamp('verified_at', { withTimezone: true }),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
    deleteAfter: timestamp('delete_after', { withTimezone: true }).notNull(),
    deletionStatus: text('deletion_status').notNull().default('pending'),
    deletionAttempts: integer('deletion_attempts').notNull().default(0),
    deletionLastError: text('deletion_last_error'),
  },
  (t) => ({
    deviceCreatedIdx: index('asset_device_created_idx').on(t.ownerDeviceId, t.createdAt.desc()),
    // Drizzle can't model this partial predicate — the raw migration carries the WHERE clause.
    dedupIdx: uniqueIndex('asset_dedup_per_device').on(t.ownerDeviceId, t.sha256),
  }),
);

export const LINK_STATUSES = ['active', 'expired', 'revoked'] as const;
export type LinkStatus = (typeof LINK_STATUSES)[number];

export const RETENTION_POLICIES = ['oneHour', 'oneDay', 'oneWeek', 'oneMonth', 'custom'] as const;
export type RetentionPolicy = (typeof RETENTION_POLICIES)[number];

export const shareLink = pgTable(
  'share_link',
  {
    id: uuid('id')
      .primaryKey()
      .default(sql`gen_random_uuid()`),
    token: text('token').notNull().unique(),
    assetId: uuid('asset_id')
      .notNull()
      .references(() => asset.id),
    // visibility: 'public' | 'signed' | 'password' (CHECK in SQL).
    visibility: text('visibility').notNull(),
    passwordHash: text('password_hash'),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    hits: bigint('hits', { mode: 'number' }).notNull().default(0),
    linkStatus: text('link_status').notNull().default('active'),
    retentionPolicy: text('retention_policy').notNull(),
    revokedAt: timestamp('revoked_at', { withTimezone: true }),
    lastAccessedAt: timestamp('last_accessed_at', { withTimezone: true }),
    accessCount: bigint('access_count', { mode: 'number' }).notNull().default(0),
    maxAccessCount: bigint('max_access_count', { mode: 'number' }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    assetIdx: index('share_link_asset_idx').on(t.assetId),
    // Partial predicate (link_status = 'active') lives in the SQL migration.
    activeExpiresIdx: index('share_link_active_expires_idx').on(t.expiresAt),
  }),
);

export const uploadJob = pgTable(
  'upload_job',
  {
    id: uuid('id')
      .primaryKey()
      .default(sql`gen_random_uuid()`),
    deviceId: uuid('device_id')
      .notNull()
      .references(() => device.id),
    assetId: uuid('asset_id').references(() => asset.id),
    clientJobId: text('client_job_id').notNull(),
    status: text('status').notNull(),
    errorCode: text('error_code'),
    retentionPolicy: text('retention_policy'),
    expiresAt: timestamp('expires_at', { withTimezone: true }),
    deleteAfter: timestamp('delete_after', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    deviceClientJobUnique: uniqueIndex('upload_job_device_client_job_unique').on(
      t.deviceId,
      t.clientJobId,
    ),
  }),
);

export const DELETION_JOB_STATUSES = ['pending', 'running', 'done', 'failed'] as const;
export type DeletionJobStatus = (typeof DELETION_JOB_STATUSES)[number];

export const deletionJob = pgTable(
  'deletion_job',
  {
    id: uuid('id')
      .primaryKey()
      .default(sql`gen_random_uuid()`),
    assetId: uuid('asset_id')
      .notNull()
      .references(() => asset.id, { onDelete: 'cascade' }),
    scheduledFor: timestamp('scheduled_for', { withTimezone: true }).notNull(),
    status: text('status').notNull().default('pending'),
    attempts: integer('attempts').notNull().default(0),
    lastError: text('last_error'),
    lockedAt: timestamp('locked_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    // Both partial predicates (active-only, pending-only) live in the SQL migration.
    activePerAssetIdx: uniqueIndex('deletion_job_active_per_asset').on(t.assetId),
    dueIdx: index('deletion_job_due_idx').on(t.scheduledFor),
  }),
);

// Apple IAP product IDs map to these tiers. `lifetime` skips renewal — its
// `expiresAt` stays NULL forever.
export const SUBSCRIPTION_TIERS = ['monthly', 'annual', 'lifetime'] as const;
export type SubscriptionTier = (typeof SUBSCRIPTION_TIERS)[number];

// Status vocabulary covers the canonical Apple App Store Server Notifications v2
// outcomes we care about. CHECK constraints live in the SQL migration.
export const SUBSCRIPTION_STATUSES = [
  'active',
  'expired',
  'in_grace',
  'in_billing_retry',
  'revoked',
  'refunded',
] as const;
export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number];

export const subscription = pgTable(
  'subscription',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    deviceId: uuid('device_id')
      .notNull()
      .references(() => device.id),
    // Apple's `originalTransactionId` is stable across renewals — this is the
    // single row we upsert on. `latestTransactionId` below moves forward.
    appleOriginalTransactionId: text('apple_original_transaction_id').notNull().unique(),
    tier: text('tier').notNull(),
    status: text('status').notNull(),
    // NULL only for lifetime; for monthly/annual this tracks the Apple
    // `expiresDate`, not the lexical "expired" status.
    expiresAt: timestamp('expires_at', { withTimezone: true }),
    autoRenewStatus: boolean('auto_renew_status').notNull().default(true),
    latestTransactionId: text('latest_transaction_id').notNull(),
    rawNotificationPayload: jsonb('raw_notification_payload'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    deviceIdx: index('subscription_device_idx').on(t.deviceId),
    // Drizzle can't model the `WHERE status = 'active'` predicate; the SQL
    // migration carries the partial unique index.
    activeDeviceIdx: uniqueIndex('subscription_active_per_device').on(t.deviceId),
  }),
);

export type User = InferSelectModel<typeof user>;
export type NewUser = InferInsertModel<typeof user>;
export type Device = InferSelectModel<typeof device>;
export type NewDevice = InferInsertModel<typeof device>;
export type Asset = InferSelectModel<typeof asset>;
export type NewAsset = InferInsertModel<typeof asset>;
export type ShareLink = InferSelectModel<typeof shareLink>;
export type NewShareLink = InferInsertModel<typeof shareLink>;
export type UploadJob = InferSelectModel<typeof uploadJob>;
export type NewUploadJob = InferInsertModel<typeof uploadJob>;
export type DeletionJob = InferSelectModel<typeof deletionJob>;
export type NewDeletionJob = InferInsertModel<typeof deletionJob>;
export type Subscription = InferSelectModel<typeof subscription>;
export type NewSubscription = InferInsertModel<typeof subscription>;
