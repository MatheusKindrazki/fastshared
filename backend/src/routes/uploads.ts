import { Hono, type Context } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { and, eq, inArray, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb, type Db } from '~/db/client';
import { bundleAsset, shareLink, uploadJob } from '~/db/schema';
import { auth } from '~/middleware/auth';
import { ratelimit } from '~/middleware/ratelimit';
import { rateLimitFreeTier } from '~/middleware/rateLimitFreeTier';
import {
  abortMultipartUpload,
  buildObjectKeyForJob,
  completeMultipartUpload,
  createMultipartUpload,
  deleteObject,
  headObject,
  presignPart,
  presignPut,
  type PresignPutResult,
} from '~/services/r2';
import { createAsset, findLiveAssetBySha256AndDevice, scheduleDeletion } from '~/services/assets';
import { activateBundleIfPending, createShareLink } from '~/services/shareLinks';
import { generateToken } from '~/lib/tokens';
import { isAllowedContentType, resolveSizeLimit } from '~/lib/sizeLimits';
import { resolveRetention } from '~/lib/retention';
import { problem } from '~/lib/problem';
import { FREE_CAPS } from '~/lib/tierCaps';
import { findActiveProForDevice, parseDevProAllowList } from '~/services/subscriptions';
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

// Bundle presign — N items, 1 share token. Mirrors the single-file shape per
// item so the client can dispatch parallel PUTs without a separate code path.
const batchItemSchema = z.object({
  clientJobId: z.string(),
  contentType: z.string(),
  sizeBytes: z.number().int().positive(),
  sha256: z.string().optional(),
  originalFilename: z.string().optional(),
});

const createBatchSchema = z.object({
  retentionPolicy: z.enum(RETENTION_POLICIES).default('oneDay'),
  visibility: z.enum(['public', 'signed', 'password']).default('signed'),
  customTtlSeconds: z.number().int().min(300).max(2_592_000).optional(),
  // Single-item batches are intentionally rejected — clients should call
  // POST /uploads instead so we don't pay the bundle wrapper for nothing.
  items: z.array(batchItemSchema).min(2).max(50),
});

type BatchItemInput = z.infer<typeof batchItemSchema>;

export const uploadRoutes = new Hono<AppBindings>();

uploadRoutes.use('*', auth());
uploadRoutes.use('*', ratelimit({ bucket: 'upload', limit: 30, windowSeconds: 600 }));
// Free-tier enforcement only on the presign endpoint — /complete and /fail
// operate on an existing job and shouldn't be gated a second time. /batch
// runs its own multi-count check inline (the middleware reads `sizeBytes`
// off the body and counts 1, which is wrong for a batch).
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

// Bundle presign: N files behind one short URL.
// Single-file requests must use POST /uploads — `items.min(2)` enforces this.
uploadRoutes.post('/batch', async (c) => {
  const body = createBatchSchema.parse(await c.req.json());
  const deviceId = requireDeviceId(c.get('deviceId'));
  const db = createDb(c.env.DATABASE_URL);

  // Per-item content-type + size validation BEFORE we reserve cap or mint
  // any DB rows — surface the bad item up front.
  for (const item of body.items) {
    if (!isAllowedContentType(item.contentType)) {
      throw new HTTPException(415, { message: `content-type not allowed: ${item.contentType}` });
    }
    const maxBytes = resolveSizeLimit(item.contentType);
    if (item.sizeBytes > maxBytes) {
      throw new HTTPException(413, {
        message: `size ${item.sizeBytes} exceeds limit ${maxBytes} for ${item.contentType}`,
      });
    }
  }

  // Free-tier enforcement: each file in the bundle counts 1 against the daily
  // cap, plus the per-file size cap. Pro skips both. Mirrors the logic in
  // rateLimitFreeTier middleware but with count = items.length atomically.
  const enforce = await enforceBatchFreeTierLimits(c, db, deviceId, body);
  if (enforce) return enforce;

  const retention = resolveRetention({
    policy: body.retentionPolicy,
    customTtlSeconds: body.customTtlSeconds,
  });

  const bundleToken = generateToken();
  const itemCount = body.items.length;

  // Pre-create the pending bundle share_link. Cleanup cron sweeps stale
  // pending bundles (no junction rows after 1h) — same safety net as single
  // pending links.
  const [bundleLink] = await db
    .insert(shareLink)
    .values({
      token: bundleToken,
      assetId: null,
      visibility: body.visibility,
      expiresAt: retention.expiresAt,
      linkStatus: 'pending',
      retentionPolicy: retention.retentionPolicy,
      isBundle: true,
      bundleAssetCount: itemCount,
    })
    .returning({ id: shareLink.id });
  if (!bundleLink) throw new Error('bundle share_link insert returned no rows');

  // Per-item presign: create upload_job + sign R2 URLs (single or multipart).
  // Neon HTTP doesn't expose transactions, so on any failure we manually
  // unwind the bundle row + every job we already minted. Best-effort — the
  // pending-link cleanup cron is the safety net for whatever slips.
  const createdJobIds: string[] = [];
  const responseItems: BatchPresignItem[] = [];
  try {
    for (const item of body.items) {
      const presigned = await presignBatchItem({
        c,
        db,
        deviceId,
        item,
        bundleToken,
        retention,
      });
      createdJobIds.push(presigned.uploadId);
      responseItems.push(presigned);
    }
  } catch (err) {
    await rollbackBatchPresign(db, bundleLink.id, createdJobIds).catch((cleanupErr) => {
      log.warn({
        msg: 'batch_presign_rollback_failed',
        requestId: c.get('requestId'),
        error: cleanupErr instanceof Error ? cleanupErr.message : String(cleanupErr),
      });
    });
    throw err;
  }

  return c.json({
    bundleToken,
    bundleShortUrl: `${c.env.SHORT_LINK_HOST}/b/${bundleToken}`,
    expiresAt: retention.expiresAt.toISOString(),
    deleteAfter: retention.deleteAfter.toISOString(),
    retentionPolicy: retention.retentionPolicy,
    itemCount,
    items: responseItems,
    ...(c.get('freeTierClampedRetention') === true
      ? { retentionClamped: true, clampedTo: 'oneDay' as const }
      : {}),
  });
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
    // Already completed — return existing link for idempotency. Bundle path
    // resolves the link via pendingShareLinkToken because share_link.assetId
    // stays null for bundles (junction table holds the M:N).
    const link = await loadIdempotentLink(db, job);
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

  // Tier 3 side-effect dedup: since presign now accepts sha256=null (to allow
  // parallel hashing on the client), first-upload dedup no longer runs there.
  // We check here instead — if this device already has a live asset with the
  // same sha256, reuse it and let the freshly-uploaded R2 object get GC'd by
  // the bucket lifecycle. Skipping this check would trip the
  // UNIQUE(owner_device_id, sha256) index on asset and explode with a 500.
  const existing = body.sha256
    ? await findLiveAssetBySha256AndDevice(db, deviceId, body.sha256)
    : null;

  let assetForLink: { id: string; deleteAfter: Date };
  if (existing) {
    assetForLink = { id: existing.id, deleteAfter: existing.deleteAfter };
    // Orphaned bytes — drop them now instead of waiting on the lifecycle rule.
    // Fire-and-forget: if R2 hiccups here, the 90-day bucket rule is the safety net.
    c.executionCtx.waitUntil(
      deleteObject({ env: c.env, key: storageKey }).catch((err) => {
        log.warn({
          msg: 'dedup_orphan_delete_failed',
          requestId: c.get('requestId'),
          key: storageKey,
          error: err instanceof Error ? err.message : String(err),
        });
      }),
    );
  } else {
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
    assetForLink = { id: createdAsset.id, deleteAfter: createdAsset.deleteAfter };
  }

  // Tier 1: flip the pending share_link minted at presign. Bundle path forks
  // here: M:N junction means we don't write share_link.assetId, just append a
  // bundle_asset row and conditionally activate when N == bundleAssetCount.
  let link: CompleteableLink | null = null;
  if (job.pendingShareLinkToken) {
    const [pending] = await db
      .select()
      .from(shareLink)
      .where(eq(shareLink.token, job.pendingShareLinkToken))
      .limit(1);
    if (pending?.isBundle) {
      link = await completeBundleAsset(db, pending, assetForLink.id, job.id);
    } else if (pending) {
      link = await flipPendingSingleLink(db, job.pendingShareLinkToken, assetForLink.id);
    }
  }
  if (!link) {
    link = await createShareLink({
      db,
      assetId: assetForLink.id,
      retentionPolicy: job.retentionPolicy,
      expiresAt: job.expiresAt,
      visibility: 'signed',
    });
  }

  // Pre-queue the deletion job for the grace-past-expiry moment. The
  // reconciliation cron is an additional safety net for anything that slips.
  // Idempotent for dedup hits (existing asset may already have a scheduled job).
  await scheduleDeletion(db, assetForLink.id, assetForLink.deleteAfter);

  await db
    .update(uploadJob)
    .set({ status: 'verified', assetId: assetForLink.id, updatedAt: sql`now()` })
    .where(eq(uploadJob.id, uploadId));

  return c.json(
    completeResponse(c.env.SHORT_LINK_HOST, assetForLink.id, link, assetForLink.deleteAfter),
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
  isBundle: boolean;
}

function completeResponse(
  shortLinkHost: string,
  assetId: string,
  link: CompleteableLink,
  deleteAfter: Date,
) {
  // Bundle short URL lives at /b/{token}; single keeps /s/{token}.
  const path = link.isBundle ? 'b' : 's';
  return {
    assetId,
    token: link.token,
    shortUrl: `${shortLinkHost}/${path}/${link.token}`,
    expiresAt: link.expiresAt.toISOString(),
    deleteAfter: deleteAfter.toISOString(),
    linkStatus: link.linkStatus,
    retentionPolicy: link.retentionPolicy,
    ...(link.isBundle ? { isBundle: true as const } : {}),
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

// Wire shape of one item in the /uploads/batch response. `mode` discriminates
// between a single-PUT URL and the multipart envelope, mirroring POST /uploads.
type BatchPresignItem = {
  clientJobId: string;
  uploadId: string;
  storageKey: string;
  contentType: string;
  sizeBytes: number;
  upload:
    | {
        mode: 'single';
        url: string;
        method: 'PUT';
        headers: Record<string, string>;
        expiresAt: string;
      }
    | {
        mode: 'multipart';
        multipartUploadId: string;
        partSize: number;
        parts: Array<{ partNumber: number; url: string; method: 'PUT' }>;
        expiresAt: string;
      };
};

const UTC_DAY_SECONDS = 86_400;

// Mirrors rateLimitFreeTier middleware but consumes `items.length` units of
// daily-cap quota in one shot. We bypass the middleware on /batch because it
// reads `sizeBytes` off the request body and counts 1 — wrong for an array
// payload. Returns a populated Response if the request is rejected (size cap,
// daily cap), or `null` if the caller may proceed.
async function enforceBatchFreeTierLimits(
  c: Context<AppBindings>,
  db: Db,
  deviceId: string,
  body: z.infer<typeof createBatchSchema>,
): Promise<Response | null> {
  const now = Date.now();
  const active = await findActiveProForDevice(
    db,
    deviceId,
    parseDevProAllowList(c.env.DEV_PRO_APPLE_USER_IDS),
  ).catch((err) => {
    log.warn({
      msg: 'batch_free_tier_sub_lookup_failed',
      requestId: c.get('requestId'),
      error: err instanceof Error ? err.message : String(err),
    });
    return null;
  });
  const isPro =
    active !== null &&
    active.status === 'active' &&
    (active.expiresAt === null || active.expiresAt.getTime() > now);
  if (isPro) return null;

  // Per-file size cap. Fail on the first oversized item — Free users get a
  // single rejection, not a list, so they know exactly which file to drop.
  const sizeLimitBytes = FREE_CAPS.maxFileSizeMB * 1024 * 1024;
  for (const item of body.items) {
    if (item.sizeBytes > sizeLimitBytes) {
      return problem(
        c,
        402,
        'free_tier_size_exceeded',
        'Payment Required',
        `Free tier is capped at ${FREE_CAPS.maxFileSizeMB} MB per upload.`,
        {
          limitMB: FREE_CAPS.maxFileSizeMB,
          actualMB: Math.ceil(item.sizeBytes / (1024 * 1024)),
          upgrade: { tier: 'pro' as const, url: 'https://fastsha.red/pricing' },
        },
      );
    }
  }

  // Retention clamp: silent for Free, mirrors the single-file middleware.
  if (retentionExceedsFreeCap(body.retentionPolicy, body.customTtlSeconds)) {
    body.retentionPolicy = 'oneDay';
    body.customTtlSeconds = undefined;
    c.set('freeTierClampedRetention', true);
  }

  // Daily-count cap. Reserve `itemCount` units atomically so a partial batch
  // can never overshoot the cap. -1 sentinel = unlimited (skip the gate).
  if (FREE_CAPS.uploadsPerDay >= 0) {
    const itemCount = body.items.length;
    const utcDate = new Date().toISOString().slice(0, 10);
    const kvKey = `ft:${deviceId}:${utcDate}`;
    const currentStr = await c.env.RATE_LIMIT.get(kvKey);
    const currentCount = currentStr ? Number(currentStr) : 0;
    const safeCount = Number.isFinite(currentCount) ? currentCount : 0;
    if (safeCount + itemCount > FREE_CAPS.uploadsPerDay) {
      const resetsAt = nextUtcMidnight().toISOString();
      return problem(
        c,
        429,
        'free_tier_daily_exceeded',
        'Too Many Requests',
        `Free tier is capped at ${FREE_CAPS.uploadsPerDay} uploads per day.`,
        {
          limit: FREE_CAPS.uploadsPerDay,
          used: safeCount,
          requested: itemCount,
          resetsAt,
          upgrade: { tier: 'pro' as const, url: 'https://fastsha.red/pricing' },
        },
      );
    }
    await c.env.RATE_LIMIT.put(kvKey, String(safeCount + itemCount), {
      expirationTtl: 2 * UTC_DAY_SECONDS,
    });
  }

  return null;
}

function retentionExceedsFreeCap(policy: string, customTtlSeconds: number | undefined): boolean {
  const maxSeconds = FREE_CAPS.maxRetentionHours * 3600;
  switch (policy) {
    case 'oneHour':
      return false;
    case 'oneDay':
      return 86_400 > maxSeconds;
    case 'oneWeek':
      return 604_800 > maxSeconds;
    case 'oneMonth':
      return 2_592_000 > maxSeconds;
    case 'custom':
      return customTtlSeconds === undefined || customTtlSeconds > maxSeconds;
    default:
      return true;
  }
}

function nextUtcMidnight(now: Date = new Date()): Date {
  const d = new Date(now);
  d.setUTCHours(24, 0, 0, 0);
  return d;
}

interface PresignBatchItemArgs {
  c: Context<AppBindings>;
  db: Db;
  deviceId: string;
  item: BatchItemInput;
  bundleToken: string;
  retention: { expiresAt: Date; deleteAfter: Date; retentionPolicy: string };
}

// Mints one upload_job + R2 presign for a single batch item. Branches on
// MULTIPART_THRESHOLD exactly like POST /uploads. The job carries
// pendingShareLinkToken=bundleToken so /complete (milestone 2) can find the
// owning bundle.
async function presignBatchItem(args: PresignBatchItemArgs): Promise<BatchPresignItem> {
  const { c, db, deviceId, item, bundleToken, retention } = args;

  const [job] = await db
    .insert(uploadJob)
    .values({
      deviceId,
      clientJobId: item.clientJobId,
      status: 'presigned',
      retentionPolicy: retention.retentionPolicy,
      expiresAt: retention.expiresAt,
      deleteAfter: retention.deleteAfter,
      pendingShareLinkToken: bundleToken,
    })
    .onConflictDoUpdate({
      target: [uploadJob.deviceId, uploadJob.clientJobId],
      set: {
        status: 'presigned',
        retentionPolicy: retention.retentionPolicy,
        expiresAt: retention.expiresAt,
        deleteAfter: retention.deleteAfter,
        pendingShareLinkToken: bundleToken,
        updatedAt: sql`now()`,
      },
    })
    .returning({
      id: uploadJob.id,
      createdAt: uploadJob.createdAt,
    });
  if (!job) throw new Error('upload_job upsert returned no rows');

  const storageKey = buildObjectKeyForJob({
    jobId: job.id,
    deviceId,
    contentType: item.contentType,
    createdAt: job.createdAt,
    originalFilename: item.originalFilename,
  });

  const expiresIn = 15 * 60;
  const presignExpiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();

  if (item.sizeBytes <= MULTIPART_THRESHOLD) {
    const presigned = await presignPut({
      env: c.env,
      key: storageKey,
      contentType: item.contentType,
      sizeBytes: item.sizeBytes,
      expiresIn,
    });
    return {
      clientJobId: item.clientJobId,
      uploadId: job.id,
      storageKey,
      contentType: item.contentType,
      sizeBytes: item.sizeBytes,
      upload: {
        mode: 'single',
        url: presigned.url,
        method: presigned.method,
        headers: presigned.headers,
        expiresAt: presigned.expiresAt,
      },
    };
  }

  const { uploadId: multipartUploadId } = await createMultipartUpload(
    c.env,
    storageKey,
    item.contentType,
  );
  const partCount = Math.ceil(item.sizeBytes / MULTIPART_PART_SIZE);
  const partUrls = await Promise.all(
    Array.from({ length: partCount }, (_, i) =>
      presignPart(c.env, storageKey, multipartUploadId, i + 1),
    ),
  );
  await db
    .update(uploadJob)
    .set({ multipartUploadId, updatedAt: sql`now()` })
    .where(eq(uploadJob.id, job.id));

  return {
    clientJobId: item.clientJobId,
    uploadId: job.id,
    storageKey,
    contentType: item.contentType,
    sizeBytes: item.sizeBytes,
    upload: {
      mode: 'multipart',
      multipartUploadId,
      partSize: MULTIPART_PART_SIZE,
      parts: partUrls.map((url, i) => ({ partNumber: i + 1, url, method: 'PUT' as const })),
      expiresAt: presignExpiresAt,
    },
  };
}

// Best-effort unwind on partial batch failure. Drops every upload_job we
// already minted and the pending bundle share_link itself. The pending-link
// cleanup cron is the safety net if anything slips through.
async function rollbackBatchPresign(
  db: Db,
  bundleShareLinkId: string,
  createdJobIds: string[],
): Promise<void> {
  if (createdJobIds.length > 0) {
    await db.delete(uploadJob).where(inArray(uploadJob.id, createdJobIds));
  }
  await db.delete(shareLink).where(eq(shareLink.id, bundleShareLinkId));
}

// Idempotency lookup for /complete: a job that's already verified resolves
// back to its owning link. Single uses share_link.assetId; bundle uses the
// pendingShareLinkToken because share_link.assetId stays null.
async function loadIdempotentLink(
  db: Db,
  job: LoadedUploadJob,
): Promise<CompleteableLink | null> {
  if (job.pendingShareLinkToken) {
    const [byToken] = await db
      .select()
      .from(shareLink)
      .where(eq(shareLink.token, job.pendingShareLinkToken))
      .limit(1);
    if (byToken) return toCompleteable(byToken);
  }
  if (job.assetId) {
    const [byAsset] = await db
      .select()
      .from(shareLink)
      .where(eq(shareLink.assetId, job.assetId))
      .limit(1);
    if (byAsset) return toCompleteable(byAsset);
  }
  return null;
}

function toCompleteable(row: {
  token: string;
  expiresAt: Date;
  retentionPolicy: string;
  linkStatus: string;
  isBundle: boolean;
}): CompleteableLink {
  return {
    token: row.token,
    expiresAt: row.expiresAt,
    retentionPolicy: row.retentionPolicy,
    linkStatus: row.linkStatus,
    isBundle: row.isBundle,
  };
}

// Single-link path: flip pending → active and pin assetId. RETURNING surfaces
// the post-update row so we can echo it back without a re-select.
async function flipPendingSingleLink(
  db: Db,
  token: string,
  assetId: string,
): Promise<CompleteableLink | null> {
  const updatedRows = await db
    .update(shareLink)
    .set({ assetId, linkStatus: 'active' })
    .where(and(eq(shareLink.token, token), eq(shareLink.linkStatus, 'pending')))
    .returning({
      token: shareLink.token,
      expiresAt: shareLink.expiresAt,
      retentionPolicy: shareLink.retentionPolicy,
      linkStatus: shareLink.linkStatus,
      isBundle: shareLink.isBundle,
    });
  // RETURNING in production filters by predicate, but the test fake is
  // permissive and may return every row — pick the matching one defensively.
  const updated = updatedRows.find((r) => r.token === token);
  return updated ? toCompleteable(updated) : null;
}

// Bundle-link path: append a junction row keyed by upload_job_id (each
// presigned slot is a distinct row, even when two slots dedup to the same
// asset), count siblings, and flip the link to active once the count matches
// bundleAssetCount. Idempotent on retry — the (shareLinkId, uploadJobId)
// lookup short-circuits a second insert.
async function completeBundleAsset(
  db: Db,
  bundle: {
    id: string;
    token: string;
    expiresAt: Date;
    retentionPolicy: string;
    linkStatus: string;
    bundleAssetCount: number | null;
  },
  assetId: string,
  uploadJobId: string,
): Promise<CompleteableLink> {
  const existing = await db
    .select()
    .from(bundleAsset)
    .where(and(eq(bundleAsset.shareLinkId, bundle.id), eq(bundleAsset.uploadJobId, uploadJobId)))
    .limit(1);
  if (existing.length === 0) {
    // displayOrder = current count. Race-tolerant only because the cleanup
    // cron + the unique index will surface duplicates as a hard failure to
    // retry rather than silently mis-order. Two concurrent /complete calls
    // for distinct upload jobs on the same bundle still get distinct orders so
    // long as the SELECT-then-INSERT happens serially per job.
    const siblings = await db
      .select()
      .from(bundleAsset)
      .where(eq(bundleAsset.shareLinkId, bundle.id));
    await db
      .insert(bundleAsset)
      .values({
        shareLinkId: bundle.id,
        assetId,
        uploadJobId,
        displayOrder: siblings.length,
      })
      .onConflictDoNothing();
  }

  const all = await db
    .select()
    .from(bundleAsset)
    .where(eq(bundleAsset.shareLinkId, bundle.id));
  const expected = bundle.bundleAssetCount ?? 0;
  let linkStatus = bundle.linkStatus;
  if (bundle.linkStatus === 'pending' && all.length >= expected && expected > 0) {
    const flipped = await activateBundleIfPending(db, bundle.id);
    if (flipped) linkStatus = 'active';
  }
  return {
    token: bundle.token,
    expiresAt: bundle.expiresAt,
    retentionPolicy: bundle.retentionPolicy,
    linkStatus,
    isBundle: true,
  };
}
