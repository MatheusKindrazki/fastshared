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
}
export interface AssetRow {
  id: string;
  ownerDeviceId: string;
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
  assetId: string;
  visibility: string;
  expiresAt: Date;
  hits: number;
  linkStatus: string;
  retentionPolicy: string;
  revokedAt: Date | null;
  lastAccessedAt: Date | null;
  accessCount: number;
  maxAccessCount: number | null;
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
  rawNotificationPayload: unknown;
  createdAt: Date;
  updatedAt: Date;
}

export interface Store {
  devices: DeviceRow[];
  assets: AssetRow[];
  shareLinks: ShareLinkRow[];
  uploadJobs: UploadJobRow[];
  deletionJobs: DeletionJobRow[];
  subscriptions: SubscriptionRow[];
}

export const store: Store = emptyStore();

function emptyStore(): Store {
  return {
    devices: [],
    assets: [],
    shareLinks: [],
    uploadJobs: [],
    deletionJobs: [],
    subscriptions: [],
  };
}

export function resetStore(): void {
  store.devices.length = 0;
  store.assets.length = 0;
  store.shareLinks.length = 0;
  store.uploadJobs.length = 0;
  store.deletionJobs.length = 0;
  store.subscriptions.length = 0;
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
  APP_STORE_CONNECT_P8_KEY_BASE64:
    'dGVzdC1wOC1wbGFjZWhvbGRlci1iYXNlNjQtZm9yLWVudi12YWxpZGF0aW9u',
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
                    conds.length === 0 || conds.some((c) => c === r.tokenHash || c === r.id),
                );
              }
              if (name === 'asset') {
                return chain<AssetRow>(
                  () => store.assets,
                  (r, conds) => {
                    if (conds.length === 0) return true;
                    if (conds.includes(r.id)) return true;
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
                  (r, conds) => conds.length === 0 || conds.some((c) => c === r.id),
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
                    };
                    store.devices.push(row);
                    out.push(row);
                  } else if (name === 'asset') {
                    const row: AssetRow = {
                      id: (v.id as string) ?? crypto.randomUUID(),
                      ownerDeviceId: v.ownerDeviceId as string,
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
                      assetId: v.assetId as string,
                      visibility: (v.visibility as string) ?? 'signed',
                      expiresAt: v.expiresAt as Date,
                      hits: 0,
                      linkStatus: (v.linkStatus as string) ?? 'active',
                      retentionPolicy: (v.retentionPolicy as string) ?? 'oneDay',
                      revokedAt: (v.revokedAt as Date | null) ?? null,
                      lastAccessedAt: (v.lastAccessedAt as Date | null) ?? null,
                      accessCount: 0,
                      maxAccessCount: (v.maxAccessCount as number | null) ?? null,
                      createdAt: new Date(),
                    };
                    store.shareLinks.push(row);
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
                      if (v && typeof v === 'object' && 'queryChunks' in (v as object)) continue;
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
                  if (name === 'asset')
                    store.assets
                      .filter((a) => matches(a as unknown as Record<string, unknown>))
                      .forEach((a) => apply(a as unknown as Record<string, unknown>));
                  if (name === 'share_link')
                    store.shareLinks
                      .filter((l) => matches(l as unknown as Record<string, unknown>))
                      .forEach((l) => apply(l as unknown as Record<string, unknown>));
                  if (name === 'upload_job')
                    store.uploadJobs
                      .filter((j) => matches(j as unknown as Record<string, unknown>))
                      .forEach((j) => apply(j as unknown as Record<string, unknown>));
                  if (name === 'deletion_job')
                    store.deletionJobs
                      .filter((j) => matches(j as unknown as Record<string, unknown>))
                      .forEach((j) => apply(j as unknown as Record<string, unknown>));
                  if (name === 'device')
                    store.devices
                      .filter((d) => matches(d as unknown as Record<string, unknown>))
                      .forEach((d) => apply(d as unknown as Record<string, unknown>));
                  if (name === 'subscription')
                    store.subscriptions
                      .filter((s) => matches(s as unknown as Record<string, unknown>))
                      .forEach((s) => apply(s as unknown as Record<string, unknown>));
                  return {
                    returning() {
                      if (name === 'share_link') return Promise.resolve(store.shareLinks.slice());
                      return Promise.resolve([{ id: 'stub' }]);
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
        delete() {
          return { where: () => Promise.resolve() };
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
  store.devices.push({ id: deviceId, tokenHash, platform: 'ios', appVersion: '0.1.0' });
  return { deviceId, token };
}
