import { Hono, type Context } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { and, eq, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb, type Db } from '~/db/client';
import { shareLink, uploadJob } from '~/db/schema';
import { auth } from '~/middleware/auth';
import { ratelimit } from '~/middleware/ratelimit';
import { rateLimitFreeTier } from '~/middleware/rateLimitFreeTier';
import {
  abortMultipartUpload,
  buildObjectKeyForJob,
  completeMultipartUpload,
  createMultipartUpload,
  headObject,
  presignPart,
  presignPut,
  type PresignPutResult,
} from '~/services/r2';
import { createAsset, findLiveAssetBySha256AndDevice, scheduleDeletion } from '~/services/assets';
import { createShareLink } from '~/services/shareLinks';
import { generateToken } from '~/lib/tokens';
import { isAllowedContentType, resolveSizeLimit } from '~/lib/sizeLimits';
import { resolveRetention } from '~/lib/retention';
import { log } from '~/lib/logger';

const RETENTION_POLICIES = ['oneHour', 'oneDay', 'oneWeek', 'oneMonth', 'custom'] as const;

// Tier 2: files larger than this threshold go through R2 multipart (parallel
// PUTs). Threshold and part size are frozen by the plan — don't tune here.
const MULTIPART_THRESHOLD = 10 * 1024 * 1024; // 10 MB
const MULTIPART_PART_SIZE = 8 * 1024 * 1024; // 8 MB per part

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
// Free-tier enforcement only on the presign endpoint — /complete and /fail
// operate on an existing job and shouldn't be gated a second time.
uploadRoutes.use('/', rateLimitFreeTier());

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

  // Dedup only when the client already has the hash. Clients that hash in
  // parallel with presign skip the server-side first-upload dedup fast-path.
  if (body.sha256) {
    const dedup = await tryDedupResponse(c, db, deviceId, body);
    if (dedup) return dedup;
  }

  // Tier 1: mint the pending share_link token up front. /complete flips
  // linkStatus from 'pending' to 'active' once R2 confirms bytes. The client
  // copies the shortUrl to clipboard the moment presign returns.
  const shareToken = generateToken();

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
      pendingShareLinkToken: shareToken,
    })
    .onConflictDoUpdate({
      target: [uploadJob.deviceId, uploadJob.clientJobId],
      set: {
        status: 'presigned',
        retentionPolicy: retention.retentionPolicy,
        expiresAt: retention.expiresAt,
        deleteAfter: retention.deleteAfter,
        pendingShareLinkToken: shareToken,
        updatedAt: sql`now()`,
      },
    })
    .returning({
      id: uploadJob.id,
      createdAt: uploadJob.createdAt,
      pendingShareLinkToken: uploadJob.pendingShareLinkToken,
    });
  if (!job) throw new Error('upload_job upsert returned no rows');

  // Pre-create the pending share_link. Use the token that actually landed on
  // the upload_job row (on re-presign the conflict-update path keeps the
  // existing value, so this keeps us stable across retries).
  const effectiveToken = job.pendingShareLinkToken ?? shareToken;
  await db
    .insert(shareLink)
    .values({
      token: effectiveToken,
      assetId: null,
      visibility: 'signed',
      expiresAt: retention.expiresAt,
      linkStatus: 'pending',
      retentionPolicy: retention.retentionPolicy,
    })
    .onConflictDoNothing({ target: shareLink.token });

  const storageKey = buildObjectKeyForJob({
    jobId: job.id,
    deviceId,
    contentType: body.contentType,
    createdAt: job.createdAt,
    originalFilename: body.originalFilename,
  });

  const expiresIn = 15 * 60;
  const presignExpiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();

  if (body.sizeBytes <= MULTIPART_THRESHOLD) {
    const presigned = await presignPut({
      env: c.env,
      key: storageKey,
      contentType: body.contentType,
      sizeBytes: body.sizeBytes,
      expiresIn,
    });
    return c.json(
      presignResponse(
        job.id,
        storageKey,
        presigned,
        body,
        c.env.R2_BUCKET_NAME,
        retention,
        c.get('freeTierClampedRetention') === true,
        effectiveToken,
        c.env.SHORT_LINK_HOST,
      ),
    );
  }

  // Tier 2: multipart branch. Mint an R2 uploadId, sign each part's PUT URL,
  // and persist the uploadId on upload_job so /complete can call
  // CompleteMultipartUpload and the abort endpoint can call Abort.
  const { uploadId: multipartUploadId } = await createMultipartUpload(
    c.env,
    storageKey,
    body.contentType,
  );
  const partCount = Math.ceil(body.sizeBytes / MULTIPART_PART_SIZE);
  const partUrls = await Promise.all(
    Array.from({ length: partCount }, (_, i) =>
      presignPart(c.env, storageKey, multipartUploadId, i + 1),
    ),
  );
  await db
    .update(uploadJob)
    .set({ multipartUploadId, updatedAt: sql`now()` })
    .where(eq(uploadJob.id, job.id));

  return c.json(
    multipartPresignResponse(
      job.id,
      storageKey,
      body,
      c.env.R2_BUCKET_NAME,
      retention,
      c.get('freeTierClampedRetention') === true,
      effectiveToken,
      c.env.SHORT_LINK_HOST,
      multipartUploadId,
      partUrls,
      presignExpiresAt,
    ),
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
    sha256: z.string().regex(/^[a-f0-9]{64}$/),
    originalFilename: z.string().min(1).max(512).optional(),
    // Tier 2: client reports each part's ETag so we can finalize multipart.
    // Omitted on the single-PUT path.
    multipart: z
      .object({
        parts: z
          .array(
            z.object({
              partNumber: z.number().int().positive(),
              eTag: z.string().min(1),
            }),
          )
          .min(1),
      })
      .optional(),
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

  // Tier 2: multipart finalization. Enforce a bidirectional contract between
  // client and server — whatever path presign took, /complete must honor the
  // same shape. Mixing paths is a client bug, so 400.
  if (job.multipartUploadId) {
    if (!body.multipart) {
      throw new HTTPException(400, {
        message: 'multipart upload started at presign but /complete omitted parts',
      });
    }
    const parts = body.multipart.parts
      .slice()
      .sort((a, b) => a.partNumber - b.partNumber)
      .map((p) => ({
        PartNumber: p.partNumber,
        ETag: stripETagQuotes(p.eTag),
      }));
    await completeMultipartUpload(c.env, storageKey, job.multipartUploadId, parts);
  } else if (body.multipart) {
    throw new HTTPException(400, {
      message: 'single-PUT upload was presigned but /complete carried multipart parts',
    });
  }

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

  // Tier 1: flip the pending share_link minted at presign. Falls back to
  // creating a fresh row if the pending one is missing (cron swept it, or
  // the caller skipped the presign path on a legacy /complete).
  let link: CompleteableLink | null = null;
  if (job.pendingShareLinkToken) {
    const updatedRows = await db
      .update(shareLink)
      .set({ assetId: createdAsset.id, linkStatus: 'active' })
      .where(
        and(
          eq(shareLink.token, job.pendingShareLinkToken),
          eq(shareLink.linkStatus, 'pending'),
        ),
      )
      .returning({
        token: shareLink.token,
        expiresAt: shareLink.expiresAt,
        retentionPolicy: shareLink.retentionPolicy,
        linkStatus: shareLink.linkStatus,
      });
    // Pick the row whose token matches the pending token we stashed. The
    // RETURNING clause will only include matched rows in production; test
    // fakes may be looser, so filter defensively.
    const updated = updatedRows.find((r) => r.token === job.pendingShareLinkToken);
    if (updated) link = updated;
  }
  if (!link) {
    link = await createShareLink({
      db,
      assetId: createdAsset.id,
      retentionPolicy: job.retentionPolicy,
      expiresAt: job.expiresAt,
      visibility: 'signed',
    });
  }

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

// Tier 2: client-triggered abort for a multipart upload that failed all its
// part retries. We reuse the auth + ownership guards from /complete/fail —
// only the device that created the upload_job can abort it. Tears down the
// R2 multipart (otherwise it lingers 24h until the cron sweep) AND deletes
// the pending share_link so the recipient's tab stops polling.
uploadRoutes.post('/:uploadId/abort-multipart', async (c) => {
  const uploadId = c.req.param('uploadId');
  const deviceId = requireDeviceId(c.get('deviceId'));
  const db = createDb(c.env.DATABASE_URL);

  const job = await loadUploadJob(db, uploadId);
  if (!job) throw new HTTPException(404, { message: 'upload_job not found' });
  if (job.deviceId !== deviceId) {
    throw new HTTPException(403, { message: 'upload_job does not belong to device' });
  }
  if (!job.multipartUploadId) {
    throw new HTTPException(409, { message: 'upload_job is not a multipart upload' });
  }

  const storageKey = buildObjectKeyForJob({
    jobId: job.id,
    deviceId,
    contentType: 'application/octet-stream', // only the jobId+date+shard matters for key reconstruction
    createdAt: job.createdAt,
  });

  try {
    await abortMultipartUpload(c.env, storageKey, job.multipartUploadId);
  } catch (err) {
    // The abort is best-effort — the 24h cron sweep catches anything we miss.
    // But we still mark the job failed + drop the pending link, because the
    // client already gave up on this upload.
    log.warn({
      msg: 'abort_multipart_r2_failed',
      requestId: c.get('requestId'),
      uploadId,
      error: err instanceof Error ? err.message : String(err),
    });
  }

  await db
    .update(uploadJob)
    .set({ status: 'failed', errorCode: 'client_abort_multipart', updatedAt: sql`now()` })
    .where(eq(uploadJob.id, uploadId));

  if (job.pendingShareLinkToken) {
    await db
      .delete(shareLink)
      .where(
        and(eq(shareLink.token, job.pendingShareLinkToken), eq(shareLink.linkStatus, 'pending')),
      );
  }

  return new Response(null, { status: 204 });
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
  pendingShareLinkToken: string | null;
  multipartUploadId: string | null;
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
      pendingShareLinkToken: uploadJob.pendingShareLinkToken,
      multipartUploadId: uploadJob.multipartUploadId,
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
    pendingShareLinkToken: r.pendingShareLinkToken ?? null,
    multipartUploadId: r.multipartUploadId ?? null,
  };
}

function presignResponse(
  uploadId: string,
  storageKey: string,
  presigned: PresignPutResult,
  body: CreateUploadInput,
  bucket: string,
  retention: { expiresAt: Date; deleteAfter: Date; retentionPolicy: string },
  retentionClamped: boolean,
  token: string,
  shortLinkHost: string,
) {
  return {
    uploadId,
    bucket,
    storageKey,
    contentType: body.contentType,
    sizeBytes: body.sizeBytes,
    // Tier 2: `mode` discriminates single vs multipart. Old clients that
    // don't read the field still see the same url/method/headers/expiresAt
    // shape one field-level deep, so the decode stays backward-compatible.
    upload: {
      mode: 'single' as const,
      url: presigned.url,
      method: presigned.method,
      headers: presigned.headers,
      expiresAt: presigned.expiresAt,
    },
    retentionPolicy: retention.retentionPolicy,
    expiresAt: retention.expiresAt.toISOString(),
    deleteAfter: retention.deleteAfter.toISOString(),
    // Tier 1: optimistic short URL. Client copies this at presign time so the
    // clipboard transition doesn't wait on the upload.
    token,
    shortUrl: `${shortLinkHost}/s/${token}`,
    linkStatus: 'pending' as const,
    ...(retentionClamped ? { retentionClamped: true, clampedTo: 'oneDay' as const } : {}),
  };
}

// Tier 2: presign response for the multipart branch. Carries the R2 uploadId,
// per-part signed PUT URLs, and part size so the client knows how to slice the
// file. Shares the retention + shortUrl envelope with the single-PUT response.
function multipartPresignResponse(
  uploadId: string,
  storageKey: string,
  body: CreateUploadInput,
  bucket: string,
  retention: { expiresAt: Date; deleteAfter: Date; retentionPolicy: string },
  retentionClamped: boolean,
  token: string,
  shortLinkHost: string,
  multipartUploadId: string,
  partUrls: string[],
  presignExpiresAt: string,
) {
  return {
    uploadId,
    bucket,
    storageKey,
    contentType: body.contentType,
    sizeBytes: body.sizeBytes,
    upload: {
      mode: 'multipart' as const,
      multipartUploadId,
      partSize: MULTIPART_PART_SIZE,
      parts: partUrls.map((url, i) => ({ partNumber: i + 1, url, method: 'PUT' as const })),
      expiresAt: presignExpiresAt,
    },
    retentionPolicy: retention.retentionPolicy,
    expiresAt: retention.expiresAt.toISOString(),
    deleteAfter: retention.deleteAfter.toISOString(),
    token,
    shortUrl: `${shortLinkHost}/s/${token}`,
    linkStatus: 'pending' as const,
    ...(retentionClamped ? { retentionClamped: true, clampedTo: 'oneDay' as const } : {}),
  };
}

// S3 returns ETags wrapped in double quotes; CompleteMultipartUpload accepts
// either form but the quotes trip some tooling. Strip them unconditionally.
function stripETagQuotes(etag: string): string {
  const trimmed = etag.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
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
