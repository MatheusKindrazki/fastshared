import { Hono, type Context } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { and, eq, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb, type Db } from '~/db/client';
import { shareLink, uploadJob } from '~/db/schema';
import { auth } from '~/middleware/auth';
import { ratelimit } from '~/middleware/ratelimit';
import { buildObjectKeyForJob, headObject, presignPut, type PresignPutResult } from '~/services/r2';
import { createAsset, findLiveAssetBySha256AndDevice, scheduleDeletion } from '~/services/assets';
import { createShareLink } from '~/services/shareLinks';
import { isAllowedContentType, resolveSizeLimit } from '~/lib/sizeLimits';
import { resolveRetention } from '~/lib/retention';
import { log } from '~/lib/logger';

const RETENTION_POLICIES = ['oneHour', 'oneDay', 'oneWeek', 'oneMonth', 'custom'] as const;

const createUploadSchema = z
  .object({
    clientJobId: z.string().uuid(),
    contentType: z.string().min(1).max(128),
    sizeBytes: z.number().int().positive(),
    sha256: z
      .string()
      .regex(/^[a-f0-9]{64}$/)
      .optional(),
    originalFilename: z.string().min(1).max(512).optional(),
    retentionPolicy: z.enum(RETENTION_POLICIES).default('oneDay'),
    customTtlSeconds: z.number().int().min(300).max(2_592_000).optional(),
  })
  .superRefine((val, ctx) => {
    if (val.retentionPolicy === 'custom' && val.customTtlSeconds === undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['customTtlSeconds'],
        message: 'customTtlSeconds is required when retentionPolicy = "custom"',
      });
    }
    if (val.retentionPolicy !== 'custom' && val.customTtlSeconds !== undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['customTtlSeconds'],
        message: 'customTtlSeconds is only allowed when retentionPolicy = "custom"',
      });
    }
  });

type CreateUploadInput = z.infer<typeof createUploadSchema>;

export const uploadRoutes = new Hono<AppBindings>();

uploadRoutes.use('*', auth());
uploadRoutes.use('*', ratelimit({ bucket: 'upload', limit: 30, windowSeconds: 600 }));

uploadRoutes.post('/', async (c) => {
  const body = createUploadSchema.parse(await c.req.json());
  const deviceId = requireDeviceId(c.get('deviceId'));

  if (!isAllowedContentType(body.contentType)) {
    throw new HTTPException(415, { message: `content-type not allowed: ${body.contentType}` });
  }
  const maxBytes = resolveSizeLimit(body.contentType);
  if (body.sizeBytes > maxBytes) {
    throw new HTTPException(413, {
      message: `size ${body.sizeBytes} exceeds limit ${maxBytes} for ${body.contentType}`,
    });
  }

  const retention = resolveRetention({
    policy: body.retentionPolicy,
    customTtlSeconds: body.customTtlSeconds,
  });

  const db = createDb(c.env.DATABASE_URL);

  if (body.sha256) {
    const dedup = await tryDedupResponse(c, db, deviceId, body);
    if (dedup) return dedup;
  }

  // Idempotency: upsert (device_id, client_job_id) so repeat calls land on the
  // same upload_job.id. Retention columns carry the ephemeral intent from
  // presign into /complete without a second request payload.
  const [job] = await db
    .insert(uploadJob)
    .values({
      deviceId,
      clientJobId: body.clientJobId,
      status: 'presigned',
      retentionPolicy: retention.retentionPolicy,
      expiresAt: retention.expiresAt,
      deleteAfter: retention.deleteAfter,
    })
    .onConflictDoUpdate({
      target: [uploadJob.deviceId, uploadJob.clientJobId],
      set: {
        status: 'presigned',
        retentionPolicy: retention.retentionPolicy,
        expiresAt: retention.expiresAt,
        deleteAfter: retention.deleteAfter,
        updatedAt: sql`now()`,
      },
    })
    .returning({ id: uploadJob.id, createdAt: uploadJob.createdAt });
  if (!job) throw new Error('upload_job upsert returned no rows');

  const storageKey = buildObjectKeyForJob({
    jobId: job.id,
    deviceId,
    contentType: body.contentType,
    createdAt: job.createdAt,
    originalFilename: body.originalFilename,
  });

  const presigned = await presignPut({
    env: c.env,
    key: storageKey,
    contentType: body.contentType,
    sizeBytes: body.sizeBytes,
  });

  return c.json(
    presignResponse(job.id, storageKey, presigned, body, c.env.R2_BUCKET_NAME, retention),
  );
});

uploadRoutes.post('/:uploadId/complete', async (c) => {
  const uploadId = c.req.param('uploadId');
  const deviceId = requireDeviceId(c.get('deviceId'));
  const db = createDb(c.env.DATABASE_URL);

  const job = await loadUploadJob(db, uploadId);
  if (!job) throw new HTTPException(404, { message: 'upload_job not found' });
  if (job.deviceId !== deviceId) {
    throw new HTTPException(403, { message: 'upload_job does not belong to device' });
  }

  if (job.assetId) {
    // Already completed — return existing link for idempotency.
    const [link] = await db
      .select()
      .from(shareLink)
      .where(eq(shareLink.assetId, job.assetId))
      .limit(1);
    if (link) {
      const deleteAfter = job.deleteAfter ?? new Date(link.expiresAt.getTime() + 86_400 * 1000);
      return c.json(completeResponse(c.env.SHORT_LINK_HOST, job.assetId, link, deleteAfter));
    }
  }

  const completeSchema = z.object({
    contentType: z.string().min(1).max(128),
    sizeBytes: z.number().int().positive(),
    sha256: z
      .string()
      .regex(/^[a-f0-9]{64}$/)
      .optional(),
    originalFilename: z.string().min(1).max(512).optional(),
  });
  const body = completeSchema.parse(await c.req.json());

  if (!job.retentionPolicy || !job.expiresAt || !job.deleteAfter) {
    throw new HTTPException(409, {
      message: 'upload_job is missing retention metadata; re-presign required',
    });
  }

  const storageKey = buildObjectKeyForJob({
    jobId: job.id,
    deviceId,
    contentType: body.contentType,
    createdAt: job.createdAt,
    originalFilename: body.originalFilename,
  });

  const head = await headObject({ env: c.env, key: storageKey });
  if (!head) {
    throw new HTTPException(409, { message: 'object not found in R2; upload not finished' });
  }
  if (head.sizeBytes !== body.sizeBytes) {
    throw new HTTPException(409, {
      message: `size mismatch: expected ${body.sizeBytes}, got ${head.sizeBytes}`,
    });
  }
  if (head.contentType && head.contentType !== body.contentType) {
    log.warn({
      msg: 'content_type_mismatch',
      requestId: c.get('requestId'),
      expected: body.contentType,
      actual: head.contentType,
      uploadId,
    });
  }

  const createdAsset = await createAsset(db, {
    ownerDeviceId: deviceId,
    bucket: c.env.R2_BUCKET_NAME,
    storageKey,
    contentType: body.contentType,
    sizeBytes: body.sizeBytes,
    sha256: body.sha256 ?? null,
    originalFilename: body.originalFilename ?? null,
    status: 'verified',
    verifiedAt: new Date(),
    deleteAfter: job.deleteAfter,
    deletionStatus: 'pending',
    deletionAttempts: 0,
  });

  const link = await createShareLink({
    db,
    assetId: createdAsset.id,
    retentionPolicy: job.retentionPolicy,
    expiresAt: job.expiresAt,
    visibility: 'signed',
  });

  // Pre-queue the deletion job for the grace-past-expiry moment. The
  // reconciliation cron is an additional safety net for anything that slips.
  await scheduleDeletion(db, createdAsset.id, job.deleteAfter);

  await db
    .update(uploadJob)
    .set({ status: 'verified', assetId: createdAsset.id, updatedAt: sql`now()` })
    .where(eq(uploadJob.id, uploadId));

  return c.json(
    completeResponse(c.env.SHORT_LINK_HOST, createdAsset.id, link, createdAsset.deleteAfter),
  );
});

const failSchema = z.object({
  errorCode: z.string().min(1).max(64).optional(),
  detail: z.string().max(1024).optional(),
});

uploadRoutes.post('/:uploadId/fail', async (c) => {
  const uploadId = c.req.param('uploadId');
  const deviceId = requireDeviceId(c.get('deviceId'));
  const db = createDb(c.env.DATABASE_URL);

  const body = failSchema.parse(await safeJson(c.req.raw));
  const job = await loadUploadJob(db, uploadId);
  if (!job) throw new HTTPException(404, { message: 'upload_job not found' });
  if (job.deviceId !== deviceId) {
    throw new HTTPException(403, { message: 'upload_job does not belong to device' });
  }

  await db
    .update(uploadJob)
    .set({
      status: 'failed',
      errorCode: body.errorCode ?? 'client_reported',
      updatedAt: sql`now()`,
    })
    .where(eq(uploadJob.id, uploadId));

  return c.json({ ok: true });
});

async function tryDedupResponse(
  c: Context<AppBindings>,
  db: Db,
  deviceId: string,
  body: CreateUploadInput,
): Promise<Response | null> {
  if (!body.sha256) return null;
  const existing = await findLiveAssetBySha256AndDevice(db, deviceId, body.sha256);
  if (!existing) return null;
  const [link] = await db
    .select()
    .from(shareLink)
    .where(and(eq(shareLink.assetId, existing.id), eq(shareLink.linkStatus, 'active')))
    .limit(1);
  if (!link) return null;
  if (link.expiresAt.getTime() <= Date.now()) return null;

  await db
    .insert(uploadJob)
    .values({
      deviceId,
      clientJobId: body.clientJobId,
      assetId: existing.id,
      status: 'deduped',
    })
    .onConflictDoUpdate({
      target: [uploadJob.deviceId, uploadJob.clientJobId],
      set: { status: 'deduped', assetId: existing.id, updatedAt: sql`now()` },
    });

  return c.json({
    deduped: {
      assetId: existing.id,
      token: link.token,
      shortUrl: `${c.env.SHORT_LINK_HOST}/s/${link.token}`,
      expiresAt: link.expiresAt.toISOString(),
      deleteAfter: existing.deleteAfter.toISOString(),
      retentionPolicy: link.retentionPolicy,
    },
  });
}

function requireDeviceId(id: string | undefined): string {
  if (!id) throw new HTTPException(401, { message: 'no device on request' });
  return id;
}

interface LoadedUploadJob {
  id: string;
  deviceId: string;
  clientJobId: string;
  status: string;
  assetId: string | null;
  createdAt: Date;
  retentionPolicy: string | null;
  expiresAt: Date | null;
  deleteAfter: Date | null;
}

async function loadUploadJob(db: Db, uploadId: string): Promise<LoadedUploadJob | null> {
  const rows = await db
    .select({
      id: uploadJob.id,
      deviceId: uploadJob.deviceId,
      clientJobId: uploadJob.clientJobId,
      status: uploadJob.status,
      assetId: uploadJob.assetId,
      createdAt: uploadJob.createdAt,
      retentionPolicy: uploadJob.retentionPolicy,
      expiresAt: uploadJob.expiresAt,
      deleteAfter: uploadJob.deleteAfter,
    })
    .from(uploadJob)
    .where(eq(uploadJob.id, uploadId))
    .limit(1);
  const r = rows[0];
  if (!r) return null;
  return {
    id: r.id,
    deviceId: r.deviceId,
    clientJobId: r.clientJobId,
    status: r.status,
    assetId: r.assetId ?? null,
    createdAt: r.createdAt,
    retentionPolicy: r.retentionPolicy ?? null,
    expiresAt: r.expiresAt ?? null,
    deleteAfter: r.deleteAfter ?? null,
  };
}

function presignResponse(
  uploadId: string,
  storageKey: string,
  presigned: PresignPutResult,
  body: CreateUploadInput,
  bucket: string,
  retention: { expiresAt: Date; deleteAfter: Date; retentionPolicy: string },
) {
  return {
    uploadId,
    bucket,
    storageKey,
    contentType: body.contentType,
    sizeBytes: body.sizeBytes,
    upload: presigned,
    retentionPolicy: retention.retentionPolicy,
    expiresAt: retention.expiresAt.toISOString(),
    deleteAfter: retention.deleteAfter.toISOString(),
  };
}

interface CompleteableLink {
  token: string;
  expiresAt: Date;
  retentionPolicy: string;
  linkStatus: string;
}

function completeResponse(
  shortLinkHost: string,
  assetId: string,
  link: CompleteableLink,
  deleteAfter: Date,
) {
  return {
    assetId,
    token: link.token,
    shortUrl: `${shortLinkHost}/s/${link.token}`,
    expiresAt: link.expiresAt.toISOString(),
    deleteAfter: deleteAfter.toISOString(),
    linkStatus: link.linkStatus,
    retentionPolicy: link.retentionPolicy,
  };
}

async function safeJson(req: Request): Promise<unknown> {
  try {
    const text = await req.text();
    if (!text) return {};
    return JSON.parse(text) as unknown;
  } catch {
    return {};
  }
}
