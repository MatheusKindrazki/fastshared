import { Hono } from 'hono';
import { and, eq, gte, ne, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb, type Db } from '~/db/client';
import {
  device,
  publication,
  publicationFile,
  publicationOpen,
  publicationVersion,
} from '~/db/schema';
import { auth } from '~/middleware/auth';
import { problem } from '~/lib/problem';
import { PUBLICATION_FREE_CAPS, PUBLICATION_PRO_CAPS } from '~/lib/tierCaps';
import {
  findActiveEntitlementForDevice,
  findActiveProForDevice,
  isProForAllUsersEnabled,
  parseAppleUserAllowList,
} from '~/services/subscriptions';
import { presignPut } from '~/services/r2';
import { unpackPublicationZip, type UnpackFailure } from '~/services/publicationZip';
import { deletePublicationVersionPrefix } from '~/services/publicationLifecycle';

export const publicationRoutes = new Hono<AppBindings>();
publicationRoutes.use('*', auth());

const inputSchema = z.object({
  title: z.string().trim().min(1).max(200).optional(),
  kind: z.enum(['site', 'pdf', 'file']),
  filename: z.string().trim().min(1).max(255),
  sizeBytes: z.number().int().positive(),
  contentType: z.string().trim().min(1).max(255),
});
type Input = z.infer<typeof inputSchema>;

const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
export function newPublicationSlug(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(10));
  return Array.from(bytes, (n) => alphabet[n & 31]).join('');
}

export function publicationUrl(slug: string, suffix: string | undefined): string | null {
  if (!suffix || !/^[a-z0-9.-]+$/.test(suffix) || suffix.startsWith('.') || suffix.endsWith('.'))
    return null;
  return `https://p-${slug}.${suffix}`;
}

async function owner(db: Db, deviceId: string): Promise<string | null> {
  const [row] = await db
    .select({ userId: device.userId })
    .from(device)
    .where(eq(device.id, deviceId))
    .limit(1);
  return row?.userId ?? null;
}

async function pro(db: Db, deviceId: string, env: AppBindings['Bindings']): Promise<boolean> {
  if (await findActiveEntitlementForDevice(db, deviceId)) return true;
  return !!(await findActiveProForDevice(
    db,
    deviceId,
    parseAppleUserAllowList(env.DEV_PRO_APPLE_USER_IDS, env.BETA_UNLIMITED_APPLE_USER_IDS),
    { proForAllUsers: isProForAllUsersEnabled(env.PRO_FOR_ALL_USERS) },
  ));
}

async function owned(db: Db, id: string, deviceId: string) {
  const [row] = await db.select().from(publication).where(eq(publication.id, id)).limit(1);
  if (!row) return null;
  const userId = await owner(db, deviceId);
  return row.ownerUserId
    ? row.ownerUserId === userId
      ? row
      : null
    : row.ownerDeviceId === deviceId
      ? row
      : null;
}

async function storedPublicationBytes(db: Db, userId: string): Promise<bigint> {
  const [row] = await db
    .select({ bytes: sql<string>`coalesce(sum(${publicationVersion.totalBytes}), 0)::text` })
    .from(publicationVersion)
    .innerJoin(publication, eq(publicationVersion.publicationId, publication.id))
    .where(
      and(
        eq(publication.ownerUserId, userId),
        ne(publication.status, 'deleted'),
        eq(publicationVersion.state, 'ready'),
      ),
    );
  return BigInt(row?.bytes ?? '0');
}

async function uploadSlot(
  c: Parameters<typeof problem>[0],
  id: string,
  slug: string,
  number: number,
  input: Input,
  db: Db,
) {
  const url = publicationUrl(slug, c.env.PUBLICATION_HOST_SUFFIX);
  if (!url)
    return problem(
      c,
      503,
      'publication_host_unavailable',
      'Service Unavailable',
      'publication host is not configured',
    );
  const versionId = crypto.randomUUID();
  const uploadKey = `pub/${id}/v${number}/_source`;
  const uploadContentType = input.kind === 'site' ? 'application/zip' : input.contentType;
  const upload = await presignPut({
    env: c.env,
    bucketName: c.env.PUBLICATION_BUCKET_NAME,
    key: uploadKey,
    contentType: uploadContentType,
    sizeBytes: input.sizeBytes,
  });
  await db
    .insert(publicationVersion)
    .values({
      id: versionId,
      publicationId: id,
      number,
      kind: input.kind,
      uploadKey,
      uploadSizeBytes: input.sizeBytes,
      uploadContentType,
    })
    .returning();
  return c.json(
    {
      id,
      slug,
      url,
      version: number,
      upload: { url: upload.url, method: upload.method, headers: upload.headers },
    },
    201,
  );
}

publicationRoutes.post('/', async (c) => {
  if (!publicationUrl('aaaaaaaaaa', c.env.PUBLICATION_HOST_SUFFIX))
    return problem(c, 503, 'publication_host_unavailable', 'Service Unavailable');
  const parsed = inputSchema.safeParse(await c.req.json().catch(() => null));
  if (!parsed.success)
    return problem(c, 400, 'invalid_publication', 'Bad Request', 'invalid publication');
  const db = createDb(c.env.DATABASE_URL);
  const deviceId = c.get('deviceId')!;
  const userId = await owner(db, deviceId);
  const isPro = await pro(db, deviceId, c.env);
  if (isPro && !userId)
    return problem(c, 403, 'account_required', 'Forbidden', 'Pro publishing requires a user');
  const caps = isPro ? PUBLICATION_PRO_CAPS : PUBLICATION_FREE_CAPS;
  if (parsed.data.sizeBytes > caps.maxUploadBytes)
    return problem(c, 413, 'upload_too_large', 'Payload Too Large');
  const rows = await db
    .select()
    .from(publication)
    .where(userId ? eq(publication.ownerUserId, userId) : eq(publication.ownerDeviceId, deviceId));
  const active = rows.filter((row) => row.status === 'active');
  if (active.length >= caps.activePublications)
    return problem(c, 402, 'publication_limit', 'Payment Required', undefined, {
      upgradeUrl: `${c.env.SHORT_LINK_HOST}/pricing`,
    });
  if (isPro) {
    const bytes = await storedPublicationBytes(db, userId!);
    if (bytes + BigInt(parsed.data.sizeBytes) > BigInt(caps.maxStorageBytes))
      return problem(c, 413, 'storage_limit', 'Payload Too Large');
  }
  const id = crypto.randomUUID();
  const slug = newPublicationSlug();
  const expiresAt = isPro ? null : new Date(Date.now() + 7 * 86400_000);
  await db
    .insert(publication)
    .values({
      id,
      slug,
      ownerUserId: userId,
      ownerDeviceId: deviceId,
      title: parsed.data.title ?? parsed.data.filename,
      expiresAt,
    })
    .returning();
  try {
    return await uploadSlot(c, id, slug, 1, parsed.data, db);
  } catch (err) {
    await db.delete(publication).where(eq(publication.id, id));
    throw err;
  }
});

publicationRoutes.post('/:id/versions', async (c) => {
  if (!publicationUrl('aaaaaaaaaa', c.env.PUBLICATION_HOST_SUFFIX))
    return problem(c, 503, 'publication_host_unavailable', 'Service Unavailable');
  const parsed = inputSchema.safeParse(await c.req.json().catch(() => null));
  if (!parsed.success)
    return problem(c, 400, 'invalid_publication', 'Bad Request', 'invalid publication');
  const db = createDb(c.env.DATABASE_URL);
  const row = await owned(db, c.req.param('id'), c.get('deviceId')!);
  if (!row) return problem(c, 404, 'not_found', 'Not Found');
  if (row.status !== 'active') return problem(c, 410, 'gone', 'Gone');
  if (!(await pro(db, c.get('deviceId')!, c.env)))
    return problem(c, 402, 'pro_required', 'Payment Required', undefined, {
      upgradeUrl: `${c.env.SHORT_LINK_HOST}/pricing`,
    });
  if (!row.ownerUserId) return problem(c, 403, 'account_required', 'Forbidden');
  if (parsed.data.sizeBytes > PUBLICATION_PRO_CAPS.maxUploadBytes)
    return problem(c, 413, 'upload_too_large', 'Payload Too Large');
  const versions = await db
    .select()
    .from(publicationVersion)
    .where(eq(publicationVersion.publicationId, row.id));
  const used = await storedPublicationBytes(db, row.ownerUserId);
  if (used + BigInt(parsed.data.sizeBytes) > BigInt(PUBLICATION_PRO_CAPS.maxStorageBytes))
    return problem(c, 413, 'storage_limit', 'Payload Too Large');
  return uploadSlot(
    c,
    row.id,
    row.slug,
    Math.max(0, ...versions.map((v) => v.number)) + 1,
    parsed.data,
    db,
  );
});

publicationRoutes.post('/:id/versions/:n/complete', async (c) => {
  const db = createDb(c.env.DATABASE_URL);
  const row = await owned(db, c.req.param('id'), c.get('deviceId')!);
  if (!row) return problem(c, 404, 'not_found', 'Not Found');
  if (row.status !== 'active') return problem(c, 410, 'gone', 'Gone');
  const number = Number(c.req.param('n'));
  const [version] = await db
    .select()
    .from(publicationVersion)
    .where(and(eq(publicationVersion.publicationId, row.id), eq(publicationVersion.number, number)))
    .limit(1);
  if (!version) return problem(c, 404, 'not_found', 'Not Found');
  const url = publicationUrl(row.slug, c.env.PUBLICATION_HOST_SUFFIX)!;
  if (version.state === 'ready')
    return c.json({
      url,
      version: number,
      fileCount: version.fileCount,
      totalBytes: version.totalBytes,
    });
  if (version.state === 'failed') return problem(c, 409, 'version_failed', 'Conflict');
  const obj = await c.env.PUBLICATIONS.get(version.uploadKey);
  if (
    !obj ||
    obj.size !== version.uploadSizeBytes ||
    (obj.httpMetadata?.contentType && obj.httpMetadata.contentType !== version.uploadContentType)
  )
    return problem(c, 409, 'upload_incomplete', 'Conflict');
  let files: Array<{ path: string; storageKey: string; contentType: string; sizeBytes: number }>;
  let entryPath: string;
  try {
    if (version.kind === 'site') {
      const result = await unpackPublicationZip(
        c.env.PUBLICATIONS,
        version.uploadKey,
        obj.size,
        row.id,
        number,
        (await pro(db, c.get('deviceId')!, c.env))
          ? PUBLICATION_PRO_CAPS.maxUploadBytes
          : PUBLICATION_FREE_CAPS.maxUploadBytes,
      );
      files = result.files;
      entryPath = result.entryPath;
    } else {
      const path = version.kind === 'pdf' ? 'index.pdf' : 'download';
      files = [
        {
          path,
          storageKey: version.uploadKey,
          contentType: version.kind === 'pdf' ? 'application/pdf' : version.uploadContentType,
          sizeBytes: obj.size,
        },
      ];
      entryPath = path;
    }
  } catch (err) {
    try {
      await deletePublicationVersionPrefix(c.env, row.id, number);
    } finally {
      await db
        .update(publicationVersion)
        .set({ state: 'failed' })
        .where(eq(publicationVersion.id, version.id));
    }
    const failure = err as UnpackFailure;
    return problem(c, 422, 'unpack_error', 'Unprocessable Content', failure.message, {
      unpack_error: failure.code ?? 'invalid_zip',
    });
  }
  const totalBytes = files.reduce((n, f) => n + f.sizeBytes, 0);
  if (row.ownerUserId && (await pro(db, c.get('deviceId')!, c.env))) {
    const storedBytes = await storedPublicationBytes(db, row.ownerUserId);
    if (storedBytes + BigInt(totalBytes) > BigInt(PUBLICATION_PRO_CAPS.maxStorageBytes)) {
      if (version.kind === 'site')
        await Promise.all(files.map((f) => c.env.PUBLICATIONS.delete(f.storageKey)));
      return problem(c, 413, 'storage_limit', 'Payload Too Large');
    }
  }
  for (const file of files)
    await db
      .insert(publicationFile)
      .values({ versionId: version.id, ...file })
      .onConflictDoNothing();
  await db
    .update(publicationVersion)
    .set({ state: 'ready', entryPath, fileCount: files.length, totalBytes })
    .where(eq(publicationVersion.id, version.id));
  await db
    .update(publication)
    .set({ currentVersionId: version.id, updatedAt: new Date() })
    .where(eq(publication.id, row.id));
  if (version.kind === 'site') await c.env.PUBLICATIONS.delete(version.uploadKey);
  await c.env.RATE_LIMIT.delete(`pub:cache:${row.slug}`);
  return c.json({ url, version: number, fileCount: files.length, totalBytes });
});

publicationRoutes.get('/', async (c) => {
  const db = createDb(c.env.DATABASE_URL);
  const deviceId = c.get('deviceId')!;
  const userId = await owner(db, deviceId);
  const rows = await db
    .select()
    .from(publication)
    .where(userId ? eq(publication.ownerUserId, userId) : eq(publication.ownerDeviceId, deviceId));
  const versions = await db.select().from(publicationVersion);
  const cutoff = new Date(Date.now() - 7 * 86400_000);
  const opens = await db
    .select()
    .from(publicationOpen)
    .where(gte(publicationOpen.openedAt, cutoff));
  return c.json({
    publications: rows.map((row) => ({
      id: row.id,
      slug: row.slug,
      url: publicationUrl(row.slug, c.env.PUBLICATION_HOST_SUFFIX),
      title: row.title,
      status: row.status,
      currentVersion: versions.find((v) => v.id === row.currentVersionId)?.number ?? null,
      expires_at: row.expiresAt?.toISOString() ?? null,
      opensLast7Days: opens.filter((o) => o.publicationId === row.id && o.openedAt >= cutoff)
        .length,
    })),
  });
});

publicationRoutes.post('/:id/revoke', async (c) => {
  const db = createDb(c.env.DATABASE_URL);
  const row = await owned(db, c.req.param('id'), c.get('deviceId')!);
  if (!row) return problem(c, 404, 'not_found', 'Not Found');
  await db
    .update(publication)
    .set({ status: 'revoked', updatedAt: new Date() })
    .where(eq(publication.id, row.id));
  await c.env.RATE_LIMIT.delete(`pub:cache:${row.slug}`);
  // A failed delete stays visible as revoked for the cron to retry.
  c.executionCtx.waitUntil(
    import('~/services/publicationLifecycle')
      .then((m) => m.deletePublicationPrefix(c.env, row.id))
      .catch(() => undefined),
  );
  return c.json({ id: row.id, status: 'revoked' });
});

publicationRoutes.get('/:id/opens', async (c) => {
  const db = createDb(c.env.DATABASE_URL);
  const row = await owned(db, c.req.param('id'), c.get('deviceId')!);
  if (!row) return problem(c, 404, 'not_found', 'Not Found');
  const versions = await db
    .select()
    .from(publicationVersion)
    .where(eq(publicationVersion.publicationId, row.id));
  const opens = await db
    .select()
    .from(publicationOpen)
    .where(eq(publicationOpen.publicationId, row.id));
  return c.json({
    versions: versions.map((v) => {
      const matching = opens.filter((o) => o.versionId === v.id);
      return {
        version: v.number,
        count: matching.length,
        lastOpenedAt: matching.length
          ? new Date(Math.max(...matching.map((o) => o.openedAt.getTime()))).toISOString()
          : null,
      };
    }),
  });
});
