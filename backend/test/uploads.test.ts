import { describe, expect, it, beforeEach, vi } from 'vitest';

// Hand-rolled in-memory fake of the drizzle query surface. No schema fidelity,
// just enough of the API the routes and services actually call.
interface Device {
  id: string;
  tokenHash: string;
  platform: string;
  appVersion: string;
}
interface Asset {
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
interface ShareLink {
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
interface UploadJob {
  id: string;
  deviceId: string;
  clientJobId: string;
  assetId: string | null;
  status: string;
  retentionPolicy: string | null;
  expiresAt: Date | null;
  deleteAfter: Date | null;
  pendingShareLinkToken: string | null;
  multipartUploadId: string | null;
  createdAt: Date;
}
interface DeletionJob {
  id: string;
  assetId: string;
  scheduledFor: Date;
  status: string;
  attempts: number;
}

interface Store {
  devices: Device[];
  assets: Asset[];
  shareLinks: ShareLink[];
  uploadJobs: UploadJob[];
  deletionJobs: DeletionJob[];
}

let store: Store;
function freshStore(): Store {
  return { devices: [], assets: [], shareLinks: [], uploadJobs: [], deletionJobs: [] };
}

vi.mock('~/db/client', () => {
  // Walks the drizzle SQL AST to extract the string Param values used in the
  // WHERE clause. Good enough to filter by single-column eq() matches in
  // these tests — we intentionally don't reimplement drizzle's full predicate.
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

  function fakeDb() {
    return {
      select(shape?: Record<string, unknown>) {
        return {
          from(table: { _: { name: string } }) {
            const name = tableName(table);
            if (name === 'device') {
              return chain<Device>(
                () => store.devices,
                (r, conds) =>
                  conds.length === 0 || conds.some((c) => c === r.tokenHash || c === r.id),
              );
            }
            if (name === 'asset') {
              return chain<Asset>(
                () => store.assets,
                (r, conds) => {
                  if (conds.length === 0) return true;
                  // id lookup: exact match. sha256+device lookup: require both known fields
                  // to appear as literal params and the row's status to not be 'deleted'.
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
                  }) as unknown as ShareLink[];
                }
                return store.shareLinks;
              };
              return chain<ShareLink>(
                baseRows,
                (r, conds) =>
                  conds.length === 0 ||
                  conds.some((c) => c === r.token || c === r.assetId || c === r.id),
              );
            }
            if (name === 'upload_job') {
              return chain<UploadJob>(
                () => store.uploadJobs,
                (r, conds) => conds.length === 0 || conds.some((c) => c === r.id),
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
                  const row: Device = {
                    id: (v.id as string) ?? crypto.randomUUID(),
                    tokenHash: v.tokenHash as string,
                    platform: v.platform as string,
                    appVersion: v.appVersion as string,
                  };
                  store.devices.push(row);
                  out.push(row);
                } else if (name === 'asset') {
                  const row: Asset = {
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
                  const row: ShareLink = {
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
                  const row: UploadJob = {
                    id: crypto.randomUUID(),
                    deviceId: v.deviceId as string,
                    clientJobId: v.clientJobId as string,
                    assetId: (v.assetId as string | null) ?? null,
                    status: v.status as string,
                    retentionPolicy: (v.retentionPolicy as string | null) ?? null,
                    expiresAt: (v.expiresAt as Date | null) ?? null,
                    deleteAfter: (v.deleteAfter as Date | null) ?? null,
                    pendingShareLinkToken: (v.pendingShareLinkToken as string | null) ?? null,
                    multipartUploadId: (v.multipartUploadId as string | null) ?? null,
                    createdAt: new Date(),
                  };
                  store.uploadJobs.push(row);
                  out.push(row);
                } else if (name === 'deletion_job') {
                  const existing = store.deletionJobs.find(
                    (j) =>
                      j.assetId === v.assetId && (j.status === 'pending' || j.status === 'running'),
                  );
                  if (existing && conflictSet === 'nothing') {
                    out.push(existing);
                    continue;
                  }
                  const row: DeletionJob = {
                    id: crypto.randomUUID(),
                    assetId: v.assetId as string,
                    scheduledFor: (v.scheduledFor as Date) ?? new Date(),
                    status: (v.status as string) ?? 'pending',
                    attempts: 0,
                  };
                  store.deletionJobs.push(row);
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
              where() {
                // Without a real WHERE evaluator we apply the patch to every row of the
                // table; tests set up stores with exactly the rows they expect to match.
                const apply = (target: Record<string, unknown>) => {
                  for (const [k, v] of Object.entries(patch)) {
                    if (v && typeof v === 'object' && 'queryChunks' in (v as object)) continue;
                    target[k] = v;
                  }
                };
                if (name === 'asset')
                  store.assets.forEach((a) => apply(a as unknown as Record<string, unknown>));
                if (name === 'share_link')
                  store.shareLinks.forEach((l) => apply(l as unknown as Record<string, unknown>));
                if (name === 'upload_job')
                  store.uploadJobs.forEach((j) => apply(j as unknown as Record<string, unknown>));
                if (name === 'deletion_job')
                  store.deletionJobs.forEach((j) => apply(j as unknown as Record<string, unknown>));
                if (name === 'device')
                  store.devices.forEach((d) => apply(d as unknown as Record<string, unknown>));

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
      delete(table: { _: { name: string } }) {
        const name = tableName(table);
        return {
          where(cond: unknown) {
            const conds = extractParamStrings(cond);
            if (name === 'share_link') {
              // Delete rows whose token or assetId appears in the WHERE params.
              store.shareLinks = store.shareLinks.filter(
                (l) => !conds.some((c) => c === l.token || c === l.assetId || c === l.id),
              );
            }
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

function tableName(table: unknown): string {
  if (!table || typeof table !== 'object') return '';
  // Drizzle exposes the table name on a Symbol-keyed property; check both.
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

// R2 service mocks.
const headMock = vi.fn();
const presignPutMock = vi.fn();
const presignGetMock = vi.fn();
const createMultipartMock = vi.fn();
const presignPartMock = vi.fn();
const completeMultipartMock = vi.fn();
const abortMultipartMock = vi.fn();
vi.mock('~/services/r2', async () => {
  const actual = await vi.importActual<typeof import('~/services/r2')>('~/services/r2');
  return {
    ...actual,
    presignPut: (args: unknown) => presignPutMock(args),
    presignGet: (args: unknown) => presignGetMock(args),
    headObject: (args: unknown) => headMock(args),
    deleteObject: vi.fn(),
    createMultipartUpload: (env: unknown, key: unknown, contentType: unknown) =>
      createMultipartMock(env, key, contentType),
    presignPart: (env: unknown, key: unknown, uploadId: unknown, partNumber: unknown) =>
      presignPartMock(env, key, uploadId, partNumber),
    completeMultipartUpload: (env: unknown, key: unknown, uploadId: unknown, parts: unknown) =>
      completeMultipartMock(env, key, uploadId, parts),
    abortMultipartUpload: (env: unknown, key: unknown, uploadId: unknown) =>
      abortMultipartMock(env, key, uploadId),
  };
});

import worker from '~/index';
import type { Env } from '~/env';

const TEST_ENV: Env = {
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

function makeKv(): KVNamespace {
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
  } as unknown as KVNamespace;
}

const ctx: ExecutionContext = {
  waitUntil: () => undefined,
  passThroughOnException: () => undefined,
  props: {},
} as unknown as ExecutionContext;

async function seedDevice(): Promise<{ deviceId: string; token: string }> {
  const token = 'test-raw-token-abc';
  const { hashDeviceToken } = await import('~/services/devices');
  const tokenHash = await hashDeviceToken(token, TEST_ENV.DEVICE_TOKEN_PEPPER);
  const deviceId = crypto.randomUUID();
  store.devices.push({ id: deviceId, tokenHash, platform: 'ios', appVersion: '0.1.0' });
  return { deviceId, token };
}

async function post(path: string, body: unknown, headers: Record<string, string> = {}) {
  return worker.fetch(
    new Request(`https://api.test/${path.replace(/^\//, '')}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: JSON.stringify(body),
    }),
    TEST_ENV,
    ctx,
  );
}

// Default UA is a browser — automation detection would otherwise force
// `Accept: text/html` requests into the binary download path. Tests that want
// to exercise curl/bot behavior pass `user-agent` explicitly.
const BROWSER_UA_FOR_TESTS =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';

async function get(path: string, headers: Record<string, string> = {}) {
  return worker.fetch(
    new Request(`https://api.test/${path.replace(/^\//, '')}`, {
      headers: { 'user-agent': BROWSER_UA_FOR_TESTS, ...headers },
      redirect: 'manual',
    }),
    TEST_ENV,
    ctx,
  );
}

const BASE62_22 = /^[0-9A-Za-z]{22}$/;

describe('uploads flow', () => {
  beforeEach(() => {
    store = freshStore();
    headMock.mockReset();
    presignPutMock.mockReset();
    presignGetMock.mockReset();
    createMultipartMock.mockReset();
    presignPartMock.mockReset();
    completeMultipartMock.mockReset();
    abortMultipartMock.mockReset();
    presignPutMock.mockImplementation(
      async ({
        key,
        contentType,
        sizeBytes,
      }: {
        key: string;
        contentType: string;
        sizeBytes: number;
      }) => ({
        url: `https://r2.test/${key}?sig=x`,
        method: 'PUT',
        headers: { 'content-type': contentType, 'content-length': String(sizeBytes) },
        expiresAt: new Date(Date.now() + 900_000).toISOString(),
      }),
    );
    presignGetMock.mockImplementation(
      async ({ key }: { key: string }) => `https://r2.test/${key}?get=x`,
    );
    createMultipartMock.mockImplementation(async () => ({ uploadId: 'mpu-test-id' }));
    presignPartMock.mockImplementation(
      async (_env: unknown, key: string, uploadId: string, partNumber: number) =>
        `https://r2.test/${key}?uploadId=${uploadId}&partNumber=${partNumber}&sig=x`,
    );
    completeMultipartMock.mockImplementation(async () => undefined);
    abortMultipartMock.mockImplementation(async () => undefined);
  });

  it('presign happy path', async () => {
    const { token } = await seedDevice();
    const res = await post(
      '/v1/uploads',
      {
        clientJobId: crypto.randomUUID(),
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        originalFilename: 'a.jpg',
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      uploadId: string;
      upload: { url: string };
      retentionPolicy: string;
      expiresAt: string;
      deleteAfter: string;
    };
    expect(body.uploadId).toBeTruthy();
    expect(body.upload.url).toContain('https://r2.test/');
    expect(body.retentionPolicy).toBe('oneDay');
    expect(presignPutMock).toHaveBeenCalledOnce();
  });

  it('presign defaults expiresAt to now+24h and deleteAfter to expiresAt+24h', async () => {
    const { token } = await seedDevice();
    const t0 = Date.now();
    const res = await post(
      '/v1/uploads',
      {
        clientJobId: crypto.randomUUID(),
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        retentionPolicy: 'oneDay',
      },
      { authorization: `Bearer ${token}` },
    );
    const body = (await res.json()) as { expiresAt: string; deleteAfter: string };
    const expected = t0 + 86_400_000;
    expect(new Date(body.expiresAt).getTime()).toBeGreaterThanOrEqual(expected - 60_000);
    expect(new Date(body.expiresAt).getTime()).toBeLessThanOrEqual(expected + 60_000);
    const expectedDelete = new Date(body.expiresAt).getTime() + 86_400_000;
    expect(new Date(body.deleteAfter).getTime()).toBeGreaterThanOrEqual(expectedDelete - 60_000);
    expect(new Date(body.deleteAfter).getTime()).toBeLessThanOrEqual(expectedDelete + 60_000);
  });

  it('presign custom TTL applies to expiresAt', async () => {
    const { token } = await seedDevice();
    const t0 = Date.now();
    const res = await post(
      '/v1/uploads',
      {
        clientJobId: crypto.randomUUID(),
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        retentionPolicy: 'custom',
        customTtlSeconds: 3600,
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { expiresAt: string; retentionPolicy: string };
    expect(body.retentionPolicy).toBe('custom');
    const expected = t0 + 3_600_000;
    expect(new Date(body.expiresAt).getTime()).toBeGreaterThanOrEqual(expected - 60_000);
    expect(new Date(body.expiresAt).getTime()).toBeLessThanOrEqual(expected + 60_000);
  });

  it('duplicate clientJobId returns same uploadId', async () => {
    const { token } = await seedDevice();
    const clientJobId = crypto.randomUUID();
    const first = await post(
      '/v1/uploads',
      { clientJobId, contentType: 'image/jpeg', sizeBytes: 1024 },
      { authorization: `Bearer ${token}` },
    );
    const second = await post(
      '/v1/uploads',
      { clientJobId, contentType: 'image/jpeg', sizeBytes: 1024 },
      { authorization: `Bearer ${token}` },
    );
    const a = (await first.json()) as { uploadId: string };
    const b = (await second.json()) as { uploadId: string };
    expect(a.uploadId).toBe(b.uploadId);
  });

  it('sha256 dedup returns a live shortUrl and skips presign', async () => {
    const { deviceId, token } = await seedDevice();
    const sha = 'a'.repeat(64);
    const assetId = crypto.randomUUID();
    const inOneDay = new Date(Date.now() + 86_400_000);
    const inTwoDays = new Date(Date.now() + 2 * 86_400_000);
    store.assets.push({
      id: assetId,
      ownerDeviceId: deviceId,
      bucket: 'b',
      storageKey: 'uploads/xx/2026/04/19/preexisting.jpg',
      contentType: 'image/jpeg',
      sizeBytes: 500,
      sha256: sha,
      originalFilename: 'old.jpg',
      status: 'verified',
      createdAt: new Date(),
      verifiedAt: new Date(),
      deletedAt: null,
      deleteAfter: inTwoDays,
      deletionStatus: 'pending',
      deletionAttempts: 0,
      deletionLastError: null,
    });
    store.shareLinks.push({
      id: crypto.randomUUID(),
      token: 'abcdefghijABCDEFGHIJkl',
      assetId,
      visibility: 'signed',
      expiresAt: inOneDay,
      hits: 0,
      linkStatus: 'active',
      retentionPolicy: 'oneDay',
      revokedAt: null,
      lastAccessedAt: null,
      accessCount: 0,
      maxAccessCount: null,
      createdAt: new Date(),
    });
    const res = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'image/jpeg', sizeBytes: 500, sha256: sha },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      deduped?: {
        shortUrl: string;
        token: string;
        expiresAt: string;
        deleteAfter: string;
        retentionPolicy: string;
      };
    };
    expect(body.deduped?.shortUrl).toBe('https://fastsha.red/s/abcdefghijABCDEFGHIJkl');
    expect(body.deduped?.token).toBe('abcdefghijABCDEFGHIJkl');
    expect(body.deduped?.retentionPolicy).toBe('oneDay');
    expect(presignPutMock).not.toHaveBeenCalled();
  });

  it('sha256 dedup misses if the prior asset was deleted and presigns a fresh job', async () => {
    const { deviceId, token } = await seedDevice();
    const sha = 'b'.repeat(64);
    const assetId = crypto.randomUUID();
    const past = new Date(Date.now() - 3_600_000);
    store.assets.push({
      id: assetId,
      ownerDeviceId: deviceId,
      bucket: 'b',
      storageKey: 'uploads/xx/2026/04/18/gone.jpg',
      contentType: 'image/jpeg',
      sizeBytes: 500,
      sha256: sha,
      originalFilename: null,
      status: 'deleted',
      createdAt: new Date(Date.now() - 7_200_000),
      verifiedAt: new Date(Date.now() - 7_200_000),
      deletedAt: past,
      deleteAfter: past,
      deletionStatus: 'deleted',
      deletionAttempts: 1,
      deletionLastError: null,
    });
    const res = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'image/jpeg', sizeBytes: 500, sha256: sha },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { deduped?: unknown; uploadId?: string };
    expect(body.deduped).toBeUndefined();
    expect(body.uploadId).toBeTruthy();
    expect(presignPutMock).toHaveBeenCalledOnce();
  });

  it('complete returns a 22-char base62 token and active link', async () => {
    const { token } = await seedDevice();
    const clientJobId = crypto.randomUUID();
    const presign = await post(
      '/v1/uploads',
      { clientJobId, contentType: 'image/jpeg', sizeBytes: 1024 },
      { authorization: `Bearer ${token}` },
    );
    const { uploadId } = (await presign.json()) as { uploadId: string };
    headMock.mockResolvedValueOnce({ sizeBytes: 1024, contentType: 'image/jpeg', etag: 'x' });

    const res = await post(
      `/v1/uploads/${uploadId}/complete`,
      { contentType: 'image/jpeg', sizeBytes: 1024, sha256: 'c'.repeat(64) },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      shortUrl: string;
      token: string;
      linkStatus: string;
      retentionPolicy: string;
      expiresAt: string;
      deleteAfter: string;
      assetId: string;
    };
    expect(body.token).toMatch(BASE62_22);
    expect(body.shortUrl).toBe(`https://fastsha.red/s/${body.token}`);
    expect(body.linkStatus).toBe('active');
    expect(body.retentionPolicy).toBe('oneDay');
    expect(new Date(body.deleteAfter).getTime()).toBeGreaterThan(
      new Date(body.expiresAt).getTime(),
    );
  });

  it('complete with wrong deviceId returns 403', async () => {
    const { token } = await seedDevice();
    const clientJobId = crypto.randomUUID();
    const presign = await post(
      '/v1/uploads',
      { clientJobId, contentType: 'image/jpeg', sizeBytes: 1024 },
      { authorization: `Bearer ${token}` },
    );
    const { uploadId } = (await presign.json()) as { uploadId: string };

    const otherToken = 'other-token-xyz';
    const { hashDeviceToken } = await import('~/services/devices');
    const otherHash = await hashDeviceToken(otherToken, TEST_ENV.DEVICE_TOKEN_PEPPER);
    store.devices.push({
      id: crypto.randomUUID(),
      tokenHash: otherHash,
      platform: 'ios',
      appVersion: '0.1.0',
    });

    const res = await post(
      `/v1/uploads/${uploadId}/complete`,
      { contentType: 'image/jpeg', sizeBytes: 1024, sha256: 'd'.repeat(64) },
      { authorization: `Bearer ${otherToken}` },
    );
    expect(res.status).toBe(403);
  });

  it('presign without sha256 skips dedup even when a matching live asset exists', async () => {
    const { deviceId, token } = await seedDevice();
    const sha = 'e'.repeat(64);
    const assetId = crypto.randomUUID();
    const inOneDay = new Date(Date.now() + 86_400_000);
    const inTwoDays = new Date(Date.now() + 2 * 86_400_000);
    store.assets.push({
      id: assetId,
      ownerDeviceId: deviceId,
      bucket: 'b',
      storageKey: 'uploads/xx/2026/04/19/preexisting.jpg',
      contentType: 'image/jpeg',
      sizeBytes: 500,
      sha256: sha,
      originalFilename: 'old.jpg',
      status: 'verified',
      createdAt: new Date(),
      verifiedAt: new Date(),
      deletedAt: null,
      deleteAfter: inTwoDays,
      deletionStatus: 'pending',
      deletionAttempts: 0,
      deletionLastError: null,
    });
    store.shareLinks.push({
      id: crypto.randomUUID(),
      token: 'dedupableTokenAAAAAAAA',
      assetId,
      visibility: 'signed',
      expiresAt: inOneDay,
      hits: 0,
      linkStatus: 'active',
      retentionPolicy: 'oneDay',
      revokedAt: null,
      lastAccessedAt: null,
      accessCount: 0,
      maxAccessCount: null,
      createdAt: new Date(),
    });
    // Client hashes in parallel with presign — omits sha256 here.
    const res = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'image/jpeg', sizeBytes: 500 },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { deduped?: unknown; uploadId?: string; upload?: { url: string } };
    expect(body.deduped).toBeUndefined();
    expect(body.uploadId).toBeTruthy();
    expect(body.upload?.url).toContain('https://r2.test/');
    expect(presignPutMock).toHaveBeenCalledOnce();
  });

  // Tier 1 — optimistic short URL
  it('fresh presign inserts share_link with pending status and returns shortUrl', async () => {
    const { token } = await seedDevice();
    const res = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'image/jpeg', sizeBytes: 1024 },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      token: string;
      shortUrl: string;
      linkStatus: string;
      uploadId: string;
    };
    expect(body.token).toMatch(BASE62_22);
    expect(body.shortUrl).toBe(`https://fastsha.red/s/${body.token}`);
    expect(body.linkStatus).toBe('pending');
    // The share_link row was inserted with pending status.
    const row = store.shareLinks.find((l) => l.token === body.token);
    expect(row).toBeDefined();
    expect(row?.linkStatus).toBe('pending');
    expect(row?.assetId).toBeNull();
  });

  it('/complete flips pending share_link to active and attaches assetId', async () => {
    const { token } = await seedDevice();
    const presign = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'image/jpeg', sizeBytes: 1024 },
      { authorization: `Bearer ${token}` },
    );
    const { uploadId, token: presignToken } = (await presign.json()) as {
      uploadId: string;
      token: string;
    };
    headMock.mockResolvedValueOnce({ sizeBytes: 1024, contentType: 'image/jpeg', etag: 'x' });
    const res = await post(
      `/v1/uploads/${uploadId}/complete`,
      { contentType: 'image/jpeg', sizeBytes: 1024, sha256: 'c'.repeat(64) },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { token: string; linkStatus: string; assetId: string };
    // Same token preserved across presign → complete.
    expect(body.token).toBe(presignToken);
    expect(body.linkStatus).toBe('active');
    // share_link row in the store now carries the created assetId.
    const row = store.shareLinks.find((l) => l.token === presignToken);
    expect(row?.linkStatus).toBe('active');
    expect(row?.assetId).toBe(body.assetId);
  });

  // Tier 2 — multipart uploads
  it('presign with sizeBytes > 10MB returns a multipart plan', async () => {
    const { token } = await seedDevice();
    const size = 12 * 1024 * 1024;
    const res = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'application/octet-stream', sizeBytes: size },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      upload: {
        mode: string;
        multipartUploadId?: string;
        partSize?: number;
        parts?: Array<{ partNumber: number; url: string; method: string }>;
      };
    };
    expect(body.upload.mode).toBe('multipart');
    expect(body.upload.multipartUploadId).toBe('mpu-test-id');
    expect(body.upload.partSize).toBe(8 * 1024 * 1024);
    // 12MB / 8MB part size = 2 parts, ceil.
    expect(body.upload.parts).toHaveLength(2);
    expect(body.upload.parts?.[0]?.partNumber).toBe(1);
    expect(body.upload.parts?.[1]?.partNumber).toBe(2);
    expect(body.upload.parts?.[0]?.method).toBe('PUT');
    expect(createMultipartMock).toHaveBeenCalledOnce();
    expect(presignPartMock).toHaveBeenCalledTimes(2);
    expect(presignPutMock).not.toHaveBeenCalled();
  });

  it('presign with sizeBytes <= 10MB returns single-PUT plan', async () => {
    const { token } = await seedDevice();
    const size = 5 * 1024 * 1024;
    const res = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'application/octet-stream', sizeBytes: size },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      upload: { mode: string; url?: string; method?: string };
    };
    expect(body.upload.mode).toBe('single');
    expect(body.upload.url).toContain('https://r2.test/');
    expect(body.upload.method).toBe('PUT');
    expect(createMultipartMock).not.toHaveBeenCalled();
    expect(presignPutMock).toHaveBeenCalledOnce();
  });

  it('/complete with multipart parts calls completeMultipartUpload', async () => {
    const { token } = await seedDevice();
    const size = 12 * 1024 * 1024;
    const presign = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'application/octet-stream', sizeBytes: size },
      { authorization: `Bearer ${token}` },
    );
    const { uploadId } = (await presign.json()) as { uploadId: string };
    headMock.mockResolvedValueOnce({
      sizeBytes: size,
      contentType: 'application/octet-stream',
      etag: 'x',
    });
    const res = await post(
      `/v1/uploads/${uploadId}/complete`,
      {
        contentType: 'application/octet-stream',
        sizeBytes: size,
        sha256: 'f'.repeat(64),
        multipart: {
          parts: [
            { partNumber: 2, eTag: '"etag-2"' },
            { partNumber: 1, eTag: 'etag-1' },
          ],
        },
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    expect(completeMultipartMock).toHaveBeenCalledOnce();
    const call = completeMultipartMock.mock.calls[0];
    // Quotes stripped; parts sorted by PartNumber ascending.
    expect(call?.[2]).toBe('mpu-test-id');
    expect(call?.[3]).toEqual([
      { PartNumber: 1, ETag: 'etag-1' },
      { PartNumber: 2, ETag: 'etag-2' },
    ]);
  });

  it('/complete with multipart payload but no multipartUploadId returns 400', async () => {
    const { token } = await seedDevice();
    // Presign a small single-PUT job.
    const presign = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'image/jpeg', sizeBytes: 1024 },
      { authorization: `Bearer ${token}` },
    );
    const { uploadId } = (await presign.json()) as { uploadId: string };
    const res = await post(
      `/v1/uploads/${uploadId}/complete`,
      {
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        sha256: 'c'.repeat(64),
        multipart: { parts: [{ partNumber: 1, eTag: 'x' }] },
      },
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(400);
  });

  it('abort-multipart deletes pending share_link and marks job failed', async () => {
    const { token } = await seedDevice();
    const size = 12 * 1024 * 1024;
    const presign = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'application/octet-stream', sizeBytes: size },
      { authorization: `Bearer ${token}` },
    );
    const { uploadId, token: shareToken } = (await presign.json()) as {
      uploadId: string;
      token: string;
    };
    // Sanity: the pending link exists before abort.
    expect(store.shareLinks.find((l) => l.token === shareToken)).toBeDefined();

    const res = await post(
      `/v1/uploads/${uploadId}/abort-multipart`,
      {},
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(204);
    expect(abortMultipartMock).toHaveBeenCalledOnce();
    // Pending link gone; upload_job marked failed.
    expect(store.shareLinks.find((l) => l.token === shareToken)).toBeUndefined();
    const job = store.uploadJobs.find((j) => j.id === uploadId);
    expect(job?.status).toBe('failed');
  });

  it('/complete is idempotent when called twice with the same job', async () => {
    const { token } = await seedDevice();
    const presign = await post(
      '/v1/uploads',
      { clientJobId: crypto.randomUUID(), contentType: 'image/jpeg', sizeBytes: 1024 },
      { authorization: `Bearer ${token}` },
    );
    const { uploadId } = (await presign.json()) as { uploadId: string };
    headMock.mockResolvedValue({ sizeBytes: 1024, contentType: 'image/jpeg', etag: 'x' });

    const first = await post(
      `/v1/uploads/${uploadId}/complete`,
      { contentType: 'image/jpeg', sizeBytes: 1024, sha256: 'c'.repeat(64) },
      { authorization: `Bearer ${token}` },
    );
    const firstBody = (await first.json()) as { token: string; assetId: string };

    const second = await post(
      `/v1/uploads/${uploadId}/complete`,
      { contentType: 'image/jpeg', sizeBytes: 1024, sha256: 'c'.repeat(64) },
      { authorization: `Bearer ${token}` },
    );
    expect(second.status).toBe(200);
    const secondBody = (await second.json()) as { token: string; assetId: string };
    expect(secondBody.token).toBe(firstBody.token);
    expect(secondBody.assetId).toBe(firstBody.assetId);
    // No duplicate share_link for the same token.
    const count = store.shareLinks.filter((l) => l.token === firstBody.token).length;
    expect(count).toBe(1);
  });
});

describe('redirect', () => {
  beforeEach(() => {
    store = freshStore();
    presignGetMock.mockReset();
    presignGetMock.mockImplementation(
      async ({ key }: { key: string }) => `https://r2.test/${key}?get=x`,
    );
  });

  function seedLiveLink(overrides: Partial<ShareLink> = {}): { token: string; assetId: string } {
    const assetId = crypto.randomUUID();
    const tokenStr = overrides.token ?? 'liveTokenAAAAAAAAAAAAA';
    const deviceId = crypto.randomUUID();
    store.assets.push({
      id: assetId,
      ownerDeviceId: deviceId,
      bucket: 'b',
      storageKey: `uploads/aa/2026/04/19/${assetId}.jpg`,
      contentType: 'image/jpeg',
      sizeBytes: 100,
      sha256: null,
      originalFilename: null,
      status: 'verified',
      createdAt: new Date(),
      verifiedAt: new Date(),
      deletedAt: null,
      deleteAfter: new Date(Date.now() + 86_400_000),
      deletionStatus: 'pending',
      deletionAttempts: 0,
      deletionLastError: null,
    });
    store.shareLinks.push({
      id: crypto.randomUUID(),
      token: tokenStr,
      assetId,
      visibility: 'signed',
      expiresAt: new Date(Date.now() + 3_600_000),
      hits: 0,
      linkStatus: 'active',
      retentionPolicy: 'oneDay',
      revokedAt: null,
      lastAccessedAt: null,
      accessCount: 0,
      maxAccessCount: null,
      createdAt: new Date(),
      ...overrides,
    });
    return { token: tokenStr, assetId };
  }

  it('active link with HTML Accept → 200 HTML preview (hardened headers)', async () => {
    const { token } = seedLiveLink();
    const res = await get(`/s/${token}`, { accept: 'text/html' });
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toMatch(/text\/html/);
    expect(res.headers.get('Cache-Control')).toBe('private, no-store');
    expect(res.headers.get('X-Robots-Tag')).toBe('noindex, nofollow');
    expect(res.headers.get('Referrer-Policy')).toBe('no-referrer');
  });

  it('expired link (HTML Accept) → 410 HTML gone page and lazy-flips link_status', async () => {
    const { token } = seedLiveLink({
      token: 'expiredTokenAAAAAAAAAA',
      expiresAt: new Date(Date.now() - 60_000),
    });
    const res = await get(`/s/${token}`, { accept: 'text/html' });
    expect(res.status).toBe(410);
    expect(res.headers.get('Cache-Control')).toBe('private, no-store');
    // Lazy-expire runs via ctx.waitUntil in production; in the fake ExecutionContext
    // it runs synchronously as a promise. Await a tick so the update settles.
    await Promise.resolve();
    const row = store.shareLinks.find((l) => l.token === token);
    expect(row?.linkStatus).toBe('expired');
  });

  it('unknown token → 404', async () => {
    const res = await get('/s/doesnotexist');
    expect(res.status).toBe(404);
  });

  it('revoked link → 410', async () => {
    const { token } = seedLiveLink({
      token: 'revokedTokenAAAAAAAAAA',
      linkStatus: 'revoked',
      revokedAt: new Date(),
    });
    const res = await get(`/s/${token}`);
    expect(res.status).toBe(410);
  });
});

describe('revoke', () => {
  beforeEach(() => {
    store = freshStore();
    presignGetMock.mockReset();
    presignGetMock.mockImplementation(
      async ({ key }: { key: string }) => `https://r2.test/${key}?get=x`,
    );
  });

  async function seedOwnedLink(
    ownerDeviceId: string,
    tokenStr: string,
  ): Promise<{ assetId: string }> {
    const assetId = crypto.randomUUID();
    store.assets.push({
      id: assetId,
      ownerDeviceId,
      bucket: 'b',
      storageKey: `uploads/aa/2026/04/19/${assetId}.jpg`,
      contentType: 'image/jpeg',
      sizeBytes: 100,
      sha256: null,
      originalFilename: null,
      status: 'verified',
      createdAt: new Date(),
      verifiedAt: new Date(),
      deletedAt: null,
      deleteAfter: new Date(Date.now() + 86_400_000),
      deletionStatus: 'pending',
      deletionAttempts: 0,
      deletionLastError: null,
    });
    store.shareLinks.push({
      id: crypto.randomUUID(),
      token: tokenStr,
      assetId,
      visibility: 'signed',
      expiresAt: new Date(Date.now() + 3_600_000),
      hits: 0,
      linkStatus: 'active',
      retentionPolicy: 'oneDay',
      revokedAt: null,
      lastAccessedAt: null,
      accessCount: 0,
      maxAccessCount: null,
      createdAt: new Date(),
    });
    return { assetId };
  }

  it('owner can revoke and subsequent redirect is 410', async () => {
    const { deviceId, token } = await seedDevice();
    const linkToken = 'ownedTokenAAAAAAAAAAAA';
    await seedOwnedLink(deviceId, linkToken);

    const res = await post(
      `/v1/links/${linkToken}/revoke`,
      {},
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean; linkStatus: string };
    expect(body.ok).toBe(true);
    expect(body.linkStatus).toBe('revoked');

    const redirectRes = await get(`/s/${linkToken}`);
    expect(redirectRes.status).toBe(410);
  });

  it('non-owner gets 403', async () => {
    const { token } = await seedDevice();
    const otherDeviceId = crypto.randomUUID();
    const linkToken = 'otherTokenAAAAAAAAAAAA';
    await seedOwnedLink(otherDeviceId, linkToken);

    const res = await post(
      `/v1/links/${linkToken}/revoke`,
      {},
      { authorization: `Bearer ${token}` },
    );
    expect(res.status).toBe(403);
  });
});
