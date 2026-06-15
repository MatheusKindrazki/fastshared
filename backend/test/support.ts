// Shared fixtures for Plan A test suites. The drizzle fake mirrors the
// production query shape closely enough for the paths we exercise — it is
// deliberately minimal, not a drizzle reimplementation. Each test file calls
// `resetStore()` in `beforeEach` to wipe the shared state.

import { vi } from 'vitest';
import type { Env } from '~/env';

export interface DeviceRow {
  id: string;
  tokenHash: string;
  platform: string;
  appVersion: string;
  apnsToken?: string | null;
  apnsEnvironment?: 'development' | 'production' | null;
  apnsUpdatedAt?: Date | null;
  userId: string | null;
}
export interface UserRow {
  id: string;
  appleUserId: string | null;
  email: string | null;
  fullName: string | null;
  createdAt: Date;
  updatedAt: Date;
}
export interface AssetRow {
  id: string;
  ownerDeviceId: string;
  // Optional in fixtures: most suites only care about device ownership. The
  // account-deletion suite seeds it explicitly.
  ownerUserId?: string | null;
  bucket: string;
  storageKey: string;
  contentType: string;
  sizeBytes: number;
  sha256: string | null;
  originalFilename: string | null;
  status: string;
  createdAt: Date;
  verifiedAt: Date | null;
  deletedAt: Date | null;
  deleteAfter: Date;
  deletionStatus: string;
  deletionAttempts: number;
  deletionLastError: string | null;
}
export interface ShareLinkRow {
  id: string;
  token: string;
  assetId: string | null;
  visibility: string;
  expiresAt: Date;
  hits: number;
  linkStatus: string;
  retentionPolicy: string;
  revokedAt: Date | null;
  lastAccessedAt: Date | null;
  accessCount: number;
  notifyOnOpen?: boolean;
  maxAccessCount: number | null;
  createdAt: Date;
  isBundle?: boolean;
  bundleAssetCount?: number | null;
}
export interface BundleAssetRow {
  id: string;
  shareLinkId: string;
  assetId: string;
  uploadJobId: string;
  displayOrder: number;
  createdAt: Date;
}
export interface UploadJobRow {
  id: string;
  deviceId: string;
  clientJobId: string;
  assetId: string | null;
  status: string;
  retentionPolicy: string | null;
  expiresAt: Date | null;
  deleteAfter: Date | null;
  pendingShareLinkToken: string | null;
  createdAt: Date;
}
export interface DeletionJobRow {
  id: string;
  assetId: string;
  scheduledFor: Date;
  status: string;
  attempts: number;
}
export interface SubscriptionRow {
  id: string;
  deviceId: string;
  appleOriginalTransactionId: string;
  tier: string;
  status: string;
  expiresAt: Date | null;
  autoRenewStatus: boolean;
  latestTransactionId: string;
  verificationStatus: 'verified' | 'grace';
  verificationGraceUntil: Date | null;
  rawNotificationPayload: unknown;
  createdAt: Date;
  updatedAt: Date;
}

export interface Store {
  devices: DeviceRow[];
  users: UserRow[];
  assets: AssetRow[];
  shareLinks: ShareLinkRow[];
  uploadJobs: UploadJobRow[];
  deletionJobs: DeletionJobRow[];
  subscriptions: SubscriptionRow[];
  bundleAssets: BundleAssetRow[];
}

export const store: Store = emptyStore();

function emptyStore(): Store {
  return {
    devices: [],
    users: [],
    assets: [],
    shareLinks: [],
    uploadJobs: [],
    deletionJobs: [],
    subscriptions: [],
    bundleAssets: [],
  };
}

export function resetStore(): void {
  store.devices.length = 0;
  store.users.length = 0;
  store.assets.length = 0;
  store.shareLinks.length = 0;
  store.uploadJobs.length = 0;
  store.deletionJobs.length = 0;
  store.subscriptions.length = 0;
  store.bundleAssets.length = 0;
}

export const TEST_ENV: Env = {
  DATABASE_URL: 'postgres://test',
  R2: {} as unknown as R2Bucket,
  RATE_LIMIT: makeKv(),
  R2_ACCOUNT_ID: 'acc',
  R2_ACCESS_KEY_ID: 'k',
  R2_SECRET_ACCESS_KEY: 's',
  R2_BUCKET_NAME: 'fastshared-test',
  SHORT_LINK_HOST: 'https://fastsha.red',
  PUBLIC_API_HOST: 'https://api.fastsha.red',
  DEVICE_TOKEN_PEPPER: 'test-pepper-test-pepper-test-pepper',
  APP_ENV: 'test',
  APP_STORE_CONNECT_KEY_ID: 'TESTKEYID0',
  APP_STORE_CONNECT_ISSUER_ID: '00000000-0000-0000-0000-000000000000',
  APP_STORE_CONNECT_P8_KEY_BASE64: 'dGVzdC1wOC1wbGFjZWhvbGRlci1iYXNlNjQtZm9yLWVudi12YWxpZGF0aW9u',
  APPLE_BUNDLE_ID: 'red.fastsha.FastShared',
};

export function resetKv(): void {
  // Each test gets a fresh KVNamespace; swap reference rather than tracking
  // state leaks across suites.
  (TEST_ENV as { RATE_LIMIT: KVNamespace }).RATE_LIMIT = makeKv();
}

export function makeKv(): KVNamespace {
  const map = new Map<string, string>();
  return {
    get: async (k: string) => map.get(k) ?? null,
    put: async (k: string, v: string) => {
      map.set(k, v);
    },
    delete: async (k: string) => {
      map.delete(k);
    },
    list: async () => ({ keys: [], list_complete: true, cacheStatus: null }),
    // Expose for assertion access in tests.
    __map: map,
  } as unknown as KVNamespace;
}

export const ctx: ExecutionContext = {
  waitUntil: () => undefined,
  passThroughOnException: () => undefined,
  props: {},
} as unknown as ExecutionContext;

// ---------------------------------------------------------------------------
// Drizzle fake. Walk the SQL AST to extract literal param strings used in
// WHERE clauses; filter the store with them. Only a handful of single-column
// predicates are supported — enough for the routes/services we test.
// ---------------------------------------------------------------------------

function extractParamStrings(cond: unknown): string[] {
  const out: string[] = [];
  const visit = (node: unknown) => {
    if (!node) return;
    if (typeof node !== 'object') return;
    // inArray(col, [...]) embeds the bound values as a raw array of Param
    // objects directly inside queryChunks — recurse into bare arrays so those
    // IN members are surfaced rather than dropped (which would nuke the table).
    if (Array.isArray(node)) {
      node.forEach(visit);
      return;
    }
    const obj = node as { value?: unknown; queryChunks?: unknown[] };
    if (typeof obj.value === 'string') out.push(obj.value);
    if (Array.isArray(obj.queryChunks)) obj.queryChunks.forEach(visit);
  };
  visit(cond);
  return out;
}

function tableName(table: unknown): string {
  if (!table || typeof table !== 'object') return '';
  const candidate = table as Record<string | symbol, unknown> & { _?: { name?: string } };
  if (candidate._?.name) return candidate._.name;
  for (const sym of Object.getOwnPropertySymbols(candidate)) {
    if (String(sym).toLowerCase().includes('name')) {
      const v = candidate[sym];
      if (typeof v === 'string') return v;
    }
  }
  return '';
}

function chain<T>(
  rowsGetter: () => T[],
  filterRow?: (row: T, conds: string[]) => boolean,
): Promise<T[]> & Record<string, unknown> {
  let captured: string[] = [];
  const materialize = () => {
    const rows = rowsGetter();
    if (!filterRow || captured.length === 0) return rows;
    return rows.filter((r) => filterRow(r, captured));
  };
  const api = {
    where(cond: unknown) {
      captured = captured.concat(extractParamStrings(cond));
      return api;
    },
    leftJoin() {
      return api;
    },
    innerJoin() {
      return api;
    },
    orderBy() {
      return api;
    },
    limit() {
      return api;
    },
    then<R>(onFulfilled?: (v: T[]) => R) {
      return Promise.resolve(materialize()).then(onFulfilled);
    },
  };
  return api as unknown as Promise<T[]> & Record<string, unknown>;
}

export function installDrizzleFake(): void {
  vi.mock('~/db/client', () => {
    function fakeDb() {
      return {
        select(shape?: Record<string, unknown>) {
          return {
            from(table: { _: { name: string } }) {
              const name = tableName(table);
              if (name === 'device') {
                return chain<DeviceRow>(
                  () => store.devices,
                  (r, conds) =>
                    conds.length === 0 ||
                    conds.some((c) => c === r.tokenHash || c === r.id || c === r.userId),
                );
              }
              if (name === 'user') {
                return chain<UserRow>(
                  () => store.users,
                  (r, conds) =>
                    conds.length === 0 ||
                    conds.some((c) => c === r.id || c === r.appleUserId || c === r.email),
                );
              }
              if (name === 'asset') {
                return chain<AssetRow>(
                  () => store.assets,
                  (r, conds) => {
                    if (conds.length === 0) return true;
                    if (conds.includes(r.id)) return true;
                    // Account-deletion ownership scan:
                    // or(eq(ownerUserId), inArray(ownerDeviceId, [...])). It
                    // never carries a status literal, so gate the ownerDeviceId
                    // match on the absence of 'verified' to avoid colliding with
                    // the dedup lookup below.
                    if (r.ownerUserId !== null && r.ownerUserId !== undefined) {
                      if (conds.includes(r.ownerUserId)) return true;
                    }
                    if (!conds.includes('verified') && conds.includes(r.ownerDeviceId)) {
                      return true;
                    }
                    const byHash = r.sha256 !== null && conds.includes(r.sha256);
                    const byDevice = conds.includes(r.ownerDeviceId);
                    if (byHash && byDevice && r.status !== 'deleted' && r.deletedAt === null) {
                      return true;
                    }
                    return false;
                  },
                );
              }
              if (name === 'share_link') {
                const baseRows = () => {
                  if (shape && 'ownerDeviceId' in shape) {
                    return store.shareLinks.map((l) => {
                      const a = store.assets.find((x) => x.id === l.assetId);
                      return { ...l, ownerDeviceId: a?.ownerDeviceId ?? null };
                    }) as unknown as ShareLinkRow[];
                  }
                  return store.shareLinks;
                };
                return chain<ShareLinkRow>(
                  baseRows,
                  (r, conds) =>
                    conds.length === 0 ||
                    conds.some((c) => c === r.token || c === r.assetId || c === r.id),
                );
              }
              if (name === 'upload_job') {
                return chain<UploadJobRow>(
                  () => store.uploadJobs,
                  (r, conds) =>
                    conds.length === 0 ||
                    conds.some(
                      (c) =>
                        c === r.id ||
                        c === r.deviceId ||
                        c === r.clientJobId ||
                        c === r.pendingShareLinkToken,
                    ),
                );
              }
              if (name === 'bundle_asset') {
                return chain<BundleAssetRow>(
                  () => store.bundleAssets,
                  (r, conds) => {
                    if (conds.length === 0) return true;
                    // All extracted predicates must hit a field on the row.
                    // bundle_asset queries appear in two shapes:
                    //   - eq(shareLinkId)              → siblings list,
                    //   - and(eq(shareLinkId), eq(id)) → existence guard.
                    // OR semantics would let the guard match any junction
                    // sharing the bundle, masking real duplicates.
                    return conds.every(
                      (c) =>
                        c === r.id || c === r.shareLinkId || c === r.assetId || c === r.uploadJobId,
                    );
                  },
                );
              }
              if (name === 'subscription') {
                return chain<SubscriptionRow>(
                  () => store.subscriptions,
                  (r, conds) => {
                    if (conds.length === 0) return true;
                    // Match on either deviceId or appleOriginalTransactionId — the two
                    // lookups subscriptions.ts performs. Status is enforced by AND
                    // predicates that fall into `conds` too, so filter on that.
                    const byDevice = conds.includes(r.deviceId);
                    const byOtx = conds.includes(r.appleOriginalTransactionId);
                    const wantsActive = conds.includes('active');
                    if (wantsActive && r.status !== 'active') return false;
                    return byDevice || byOtx;
                  },
                );
              }
              return chain<unknown>(() => []);
            },
          };
        },
        insert(table: { _: { name: string } }) {
          const name = tableName(table);
          return {
            values(vals: Record<string, unknown> | Record<string, unknown>[]) {
              const list = Array.isArray(vals) ? vals : [vals];
              let conflictSet: Record<string, unknown> | 'nothing' | null = null;

              const run = () => {
                const out: unknown[] = [];
                for (const v of list) {
                  if (name === 'device') {
                    const row: DeviceRow = {
                      id: (v.id as string) ?? crypto.randomUUID(),
                      tokenHash: v.tokenHash as string,
                      platform: v.platform as string,
                      appVersion: v.appVersion as string,
                      apnsToken: (v.apnsToken as string | null) ?? null,
                      apnsEnvironment:
                        (v.apnsEnvironment as 'development' | 'production' | null) ?? null,
                      apnsUpdatedAt: (v.apnsUpdatedAt as Date | null) ?? null,
                      userId: (v.userId as string | null) ?? null,
                    };
                    store.devices.push(row);
                    out.push(row);
                  } else if (name === 'user') {
                    const row: UserRow = {
                      id: (v.id as string) ?? crypto.randomUUID(),
                      appleUserId: (v.appleUserId as string | null) ?? null,
                      email: (v.email as string | null) ?? null,
                      fullName: (v.fullName as string | null) ?? null,
                      createdAt: new Date(),
                      updatedAt: new Date(),
                    };
                    store.users.push(row);
                    out.push(row);
                  } else if (name === 'asset') {
                    const row: AssetRow = {
                      id: (v.id as string) ?? crypto.randomUUID(),
                      ownerDeviceId: v.ownerDeviceId as string,
                      ownerUserId: (v.ownerUserId as string | null) ?? null,
                      bucket: v.bucket as string,
                      storageKey: v.storageKey as string,
                      contentType: v.contentType as string,
                      sizeBytes: Number(v.sizeBytes),
                      sha256: (v.sha256 as string | null) ?? null,
                      originalFilename: (v.originalFilename as string | null) ?? null,
                      status: v.status as string,
                      createdAt: new Date(),
                      verifiedAt: (v.verifiedAt as Date | null) ?? null,
                      deletedAt: (v.deletedAt as Date | null) ?? null,
                      deleteAfter: v.deleteAfter as Date,
                      deletionStatus: (v.deletionStatus as string) ?? 'pending',
                      deletionAttempts: Number(v.deletionAttempts ?? 0),
                      deletionLastError: (v.deletionLastError as string | null) ?? null,
                    };
                    store.assets.push(row);
                    out.push(row);
                  } else if (name === 'share_link') {
                    const row: ShareLinkRow = {
                      id: crypto.randomUUID(),
                      token: (v.token as string) ?? Math.random().toString(36).slice(2, 9),
                      assetId: (v.assetId as string | null) ?? null,
                      visibility: (v.visibility as string) ?? 'signed',
                      expiresAt: v.expiresAt as Date,
                      hits: 0,
                      linkStatus: (v.linkStatus as string) ?? 'active',
                      retentionPolicy: (v.retentionPolicy as string) ?? 'oneDay',
                      revokedAt: (v.revokedAt as Date | null) ?? null,
                      lastAccessedAt: (v.lastAccessedAt as Date | null) ?? null,
                      accessCount: 0,
                      notifyOnOpen: (v.notifyOnOpen as boolean) ?? false,
                      maxAccessCount: (v.maxAccessCount as number | null) ?? null,
                      createdAt: new Date(),
                      isBundle: (v.isBundle as boolean) ?? false,
                      bundleAssetCount: (v.bundleAssetCount as number | null) ?? null,
                    };
                    store.shareLinks.push(row);
                    out.push(row);
                  } else if (name === 'bundle_asset') {
                    const row: BundleAssetRow = {
                      id: (v.id as string) ?? crypto.randomUUID(),
                      shareLinkId: v.shareLinkId as string,
                      assetId: v.assetId as string,
                      uploadJobId: v.uploadJobId as string,
                      displayOrder: Number(v.displayOrder),
                      createdAt: new Date(),
                    };
                    store.bundleAssets.push(row);
                    out.push(row);
                  } else if (name === 'upload_job') {
                    const matchIdx = store.uploadJobs.findIndex(
                      (j) => j.deviceId === v.deviceId && j.clientJobId === v.clientJobId,
                    );
                    if (matchIdx >= 0) {
                      if (conflictSet === 'nothing') {
                        out.push(store.uploadJobs[matchIdx]);
                        continue;
                      }
                      if (conflictSet && typeof conflictSet === 'object') {
                        const target = store.uploadJobs[matchIdx];
                        if (target) {
                          for (const [k, val] of Object.entries(conflictSet)) {
                            (target as unknown as Record<string, unknown>)[k] = val;
                          }
                          out.push(target);
                        }
                        continue;
                      }
                    }
                    const row: UploadJobRow = {
                      id: crypto.randomUUID(),
                      deviceId: v.deviceId as string,
                      clientJobId: v.clientJobId as string,
                      assetId: (v.assetId as string | null) ?? null,
                      status: v.status as string,
                      retentionPolicy: (v.retentionPolicy as string | null) ?? null,
                      expiresAt: (v.expiresAt as Date | null) ?? null,
                      deleteAfter: (v.deleteAfter as Date | null) ?? null,
                      pendingShareLinkToken: (v.pendingShareLinkToken as string | null) ?? null,
                      createdAt: new Date(),
                    };
                    store.uploadJobs.push(row);
                    out.push(row);
                  } else if (name === 'deletion_job') {
                    const existing = store.deletionJobs.find(
                      (j) =>
                        j.assetId === v.assetId &&
                        (j.status === 'pending' || j.status === 'running'),
                    );
                    if (existing && conflictSet === 'nothing') {
                      out.push(existing);
                      continue;
                    }
                    const row: DeletionJobRow = {
                      id: crypto.randomUUID(),
                      assetId: v.assetId as string,
                      scheduledFor: (v.scheduledFor as Date) ?? new Date(),
                      status: (v.status as string) ?? 'pending',
                      attempts: 0,
                    };
                    store.deletionJobs.push(row);
                    out.push(row);
                  } else if (name === 'subscription') {
                    // Upsert keyed on appleOriginalTransactionId.
                    const otx = v.appleOriginalTransactionId as string;
                    const matchIdx = store.subscriptions.findIndex(
                      (s) => s.appleOriginalTransactionId === otx,
                    );
                    if (matchIdx >= 0) {
                      if (conflictSet && typeof conflictSet === 'object') {
                        const target = store.subscriptions[matchIdx]!;
                        for (const [k, val] of Object.entries(conflictSet)) {
                          if (val && typeof val === 'object' && 'queryChunks' in (val as object)) {
                            // sql`now()` — substitute a fresh timestamp.
                            (target as unknown as Record<string, unknown>)[k] = new Date();
                            continue;
                          }
                          (target as unknown as Record<string, unknown>)[k] = val;
                        }
                        out.push(target);
                        continue;
                      }
                      if (conflictSet === 'nothing') {
                        out.push(store.subscriptions[matchIdx]);
                        continue;
                      }
                    }
                    const row: SubscriptionRow = {
                      id: crypto.randomUUID(),
                      deviceId: v.deviceId as string,
                      appleOriginalTransactionId: otx,
                      tier: v.tier as string,
                      status: v.status as string,
                      expiresAt: (v.expiresAt as Date | null) ?? null,
                      autoRenewStatus: (v.autoRenewStatus as boolean) ?? true,
                      latestTransactionId: v.latestTransactionId as string,
                      verificationStatus:
                        (v.verificationStatus as 'verified' | 'grace' | undefined) ?? 'verified',
                      verificationGraceUntil:
                        (v.verificationGraceUntil as Date | null | undefined) ?? null,
                      rawNotificationPayload: v.rawNotificationPayload ?? null,
                      createdAt: new Date(),
                      updatedAt: new Date(),
                    };
                    store.subscriptions.push(row);
                    out.push(row);
                  }
                }
                return out;
              };

              const api = {
                returning() {
                  return Promise.resolve(run());
                },
                onConflictDoNothing(cfg?: { target?: unknown }) {
                  conflictSet = 'nothing';
                  void cfg;
                  return api;
                },
                onConflictDoUpdate(cfg: { target?: unknown; set: Record<string, unknown> }) {
                  conflictSet = cfg.set;
                  return api;
                },
                then<T>(onFulfilled?: (v: unknown[]) => T) {
                  const result = run();
                  return Promise.resolve(result).then(onFulfilled);
                },
              };
              return api;
            },
          };
        },
        update(table: { _: { name: string } }) {
          const name = tableName(table);
          return {
            set(patch: Record<string, unknown>) {
              return {
                where(_cond?: unknown) {
                  // Walk the WHERE condition to extract literal string params
                  // for a tighter filter on multi-column predicates. Still
                  // permissive — updates with no extractable params apply to
                  // every row of the table.
                  const conds = extractParamStrings(_cond);
                  const apply = (target: Record<string, unknown>) => {
                    for (const [k, v] of Object.entries(patch)) {
                      if (v && typeof v === 'object' && 'queryChunks' in (v as object)) {
                        if (k === 'accessCount') {
                          target[k] = Number(target[k] ?? 0) + 1;
                        } else if (k === 'hits') {
                          target[k] = Number(target[k] ?? 0) + 1;
                        } else if (
                          k === 'lastAccessedAt' ||
                          k === 'updatedAt' ||
                          k === 'lastSeenAt' ||
                          k === 'apnsUpdatedAt'
                        ) {
                          target[k] = new Date();
                        }
                        continue;
                      }
                      target[k] = v;
                    }
                  };
                  const matches = (row: Record<string, unknown>): boolean => {
                    if (conds.length === 0) return true;
                    // Require at least one conds entry to match a string-ish field of the row.
                    for (const candidate of Object.values(row)) {
                      if (typeof candidate === 'string' && conds.includes(candidate)) return true;
                    }
                    return false;
                  };
                  const updatedRows: Record<string, unknown>[] = [];
                  const applyAll = <T>(rows: T[]) => {
                    rows
                      .filter((r) => matches(r as unknown as Record<string, unknown>))
                      .forEach((r) => {
                        const target = r as unknown as Record<string, unknown>;
                        apply(target);
                        updatedRows.push(target);
                      });
                  };
                  if (name === 'asset') applyAll(store.assets);
                  if (name === 'share_link') applyAll(store.shareLinks);
                  if (name === 'upload_job') applyAll(store.uploadJobs);
                  if (name === 'deletion_job') applyAll(store.deletionJobs);
                  if (name === 'device') applyAll(store.devices);
                  if (name === 'user') applyAll(store.users);
                  if (name === 'subscription') applyAll(store.subscriptions);
                  return {
                    returning() {
                      if (name === 'share_link') return Promise.resolve(updatedRows);
                      if (name === 'user') {
                        return Promise.resolve(updatedRows);
                      }
                      return Promise.resolve(
                        updatedRows.length > 0 ? updatedRows : [{ id: 'stub' }],
                      );
                    },
                    then<T>(onFulfilled?: (v: unknown) => T) {
                      return Promise.resolve(undefined).then(onFulfilled);
                    },
                  };
                },
              };
            },
          };
        },
        delete(table: { _: { name: string } }) {
          const name = tableName(table);
          return {
            where(cond?: unknown) {
              // Mirror update()'s permissive param extraction: a DELETE with no
              // extractable literal clears the whole table; otherwise drop rows
              // whose string fields intersect the captured predicate values.
              const conds = extractParamStrings(cond);
              const keep = (row: Record<string, unknown>): boolean => {
                if (conds.length === 0) return false;
                for (const candidate of Object.values(row)) {
                  if (typeof candidate === 'string' && conds.includes(candidate)) return false;
                }
                return true;
              };
              const prune = <T>(rows: T[]) => {
                const survivors = rows.filter((r) => keep(r as unknown as Record<string, unknown>));
                rows.length = 0;
                rows.push(...survivors);
              };
              if (name === 'user') prune(store.users);
              if (name === 'subscription') prune(store.subscriptions);
              if (name === 'asset') prune(store.assets);
              if (name === 'device') prune(store.devices);
              if (name === 'share_link') prune(store.shareLinks);
              if (name === 'upload_job') prune(store.uploadJobs);
              if (name === 'deletion_job') prune(store.deletionJobs);
              if (name === 'bundle_asset') prune(store.bundleAssets);
              return Promise.resolve();
            },
          };
        },
        execute<T>(_sql: unknown) {
          void _sql;
          return Promise.resolve({ rows: [] as T[] });
        },
      };
    }

    return { createDb: () => fakeDb() };
  });
}

// ---------------------------------------------------------------------------
// Seed helpers + thin HTTP client around the default worker.
// ---------------------------------------------------------------------------

export async function seedDevice(options?: {
  deviceId?: string;
  token?: string;
}): Promise<{ deviceId: string; token: string }> {
  const token = options?.token ?? 'test-raw-token-abc';
  const { hashDeviceToken } = await import('~/services/devices');
  const tokenHash = await hashDeviceToken(token, TEST_ENV.DEVICE_TOKEN_PEPPER);
  const deviceId = options?.deviceId ?? crypto.randomUUID();
  store.devices.push({
    id: deviceId,
    tokenHash,
    platform: 'ios',
    appVersion: '0.1.0',
    apnsToken: null,
    apnsEnvironment: null,
    apnsUpdatedAt: null,
    userId: null,
  });
  return { deviceId, token };
}
