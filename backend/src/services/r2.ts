import {
  AbortMultipartUploadCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListMultipartUploadsCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import type { Env } from '~/env';
import { newId } from '~/lib/id';

const CLIENT_CACHE = new WeakMap<object, S3Client>();

function getClient(env: Env): S3Client {
  const cached = CLIENT_CACHE.get(env as unknown as object);
  if (cached) return cached;
  const client = new S3Client({
    region: 'auto',
    endpoint: `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    },
    // R2 rejects the default CRC32 checksums the AWS SDK v3 injects.
    requestChecksumCalculation: 'WHEN_REQUIRED',
    responseChecksumValidation: 'WHEN_REQUIRED',
  });
  CLIENT_CACHE.set(env as unknown as object, client);
  return client;
}

export interface PresignPutArgs {
  env: Env;
  key: string;
  contentType: string;
  sizeBytes: number;
  expiresIn?: number;
}

export interface PresignPutResult {
  url: string;
  method: 'PUT';
  headers: Record<string, string>;
  expiresAt: string;
}

export async function presignPut(args: PresignPutArgs): Promise<PresignPutResult> {
  const expiresIn = args.expiresIn ?? 15 * 60;
  const cmd = new PutObjectCommand({
    Bucket: args.env.R2_BUCKET_NAME,
    Key: args.key,
    ContentType: args.contentType,
    ContentLength: args.sizeBytes,
  });
  const url = await getSignedUrl(getClient(args.env), cmd, { expiresIn });
  return {
    url,
    method: 'PUT',
    headers: {
      'content-type': args.contentType,
      'content-length': String(args.sizeBytes),
    },
    expiresAt: new Date(Date.now() + expiresIn * 1000).toISOString(),
  };
}

export interface PresignGetArgs {
  env: Env;
  key: string;
  // Default 60s — matches the redirect path TTL so a stolen URL has a tight blast radius.
  expiresIn?: number;
}

export async function presignGet(args: PresignGetArgs): Promise<string> {
  const expiresIn = args.expiresIn ?? 60;
  const cmd = new GetObjectCommand({
    Bucket: args.env.R2_BUCKET_NAME,
    Key: args.key,
  });
  return getSignedUrl(getClient(args.env), cmd, { expiresIn });
}

export interface HeadObjectResult {
  sizeBytes: number;
  contentType: string | undefined;
  etag: string | undefined;
}

export async function headObject(args: {
  env: Env;
  key: string;
}): Promise<HeadObjectResult | null> {
  try {
    const res = await getClient(args.env).send(
      new HeadObjectCommand({ Bucket: args.env.R2_BUCKET_NAME, Key: args.key }),
    );
    return {
      sizeBytes: Number(res.ContentLength ?? 0),
      contentType: res.ContentType,
      etag: res.ETag,
    };
  } catch (err) {
    if (isNotFound(err)) return null;
    throw err;
  }
}

export async function deleteObject(args: { env: Env; key: string }): Promise<void> {
  await getClient(args.env).send(
    new DeleteObjectCommand({ Bucket: args.env.R2_BUCKET_NAME, Key: args.key }),
  );
}

export interface AbortedMultipartUpload {
  key: string;
  uploadId: string;
  initiatedAt: Date | null;
}

export async function listAbortedMultipartUploads(args: {
  env: Env;
  olderThanMs: number;
}): Promise<AbortedMultipartUpload[]> {
  const cutoff = Date.now() - args.olderThanMs;
  const client = getClient(args.env);
  const result: AbortedMultipartUpload[] = [];

  let keyMarker: string | undefined;
  let uploadIdMarker: string | undefined;
  // Safety cap — a runaway bucket shouldn't blow the cron's time budget.
  for (let page = 0; page < 50; page++) {
    const res = await client.send(
      new ListMultipartUploadsCommand({
        Bucket: args.env.R2_BUCKET_NAME,
        KeyMarker: keyMarker,
        UploadIdMarker: uploadIdMarker,
      }),
    );
    for (const u of res.Uploads ?? []) {
      if (!u.Key || !u.UploadId) continue;
      const initiated = u.Initiated ? new Date(u.Initiated) : null;
      if (initiated && initiated.getTime() > cutoff) continue;
      result.push({ key: u.Key, uploadId: u.UploadId, initiatedAt: initiated });
    }
    if (!res.IsTruncated) break;
    keyMarker = res.NextKeyMarker;
    uploadIdMarker = res.NextUploadIdMarker;
    if (!keyMarker && !uploadIdMarker) break;
  }

  return result;
}

export async function abortMultipartUpload(args: {
  env: Env;
  key: string;
  uploadId: string;
}): Promise<void> {
  await getClient(args.env).send(
    new AbortMultipartUploadCommand({
      Bucket: args.env.R2_BUCKET_NAME,
      Key: args.key,
      UploadId: args.uploadId,
    }),
  );
}

export interface BuildStorageKeyArgs {
  deviceId: string;
  contentType: string;
  originalFilename?: string | undefined;
}

export function buildStorageKey(args: BuildStorageKeyArgs): string {
  const shard = args.deviceId.slice(0, 2);
  const now = new Date();
  const yyyy = now.getUTCFullYear().toString();
  const mm = (now.getUTCMonth() + 1).toString().padStart(2, '0');
  const dd = now.getUTCDate().toString().padStart(2, '0');
  const id = newId();
  const ext = inferExtension(args.contentType, args.originalFilename);
  return `uploads/${shard}/${yyyy}/${mm}/${dd}/${id}${ext ? `.${ext}` : ''}`;
}

export interface BuildObjectKeyForJobArgs {
  jobId: string;
  deviceId: string;
  contentType: string;
  createdAt: Date;
  originalFilename?: string | undefined;
}

// Deterministic key from (upload_job.id, upload_job.created_at) — guarantees
// idempotent presign calls for the same (device_id, client_job_id) re-use the
// same R2 object, even if /complete runs on a later day than /uploads.
export function buildObjectKeyForJob(args: BuildObjectKeyForJobArgs): string {
  const shard = args.deviceId.slice(0, 2);
  const d = args.createdAt;
  const yyyy = d.getUTCFullYear().toString();
  const mm = (d.getUTCMonth() + 1).toString().padStart(2, '0');
  const dd = d.getUTCDate().toString().padStart(2, '0');
  const ext = inferExtension(args.contentType, args.originalFilename);
  return `uploads/${shard}/${yyyy}/${mm}/${dd}/${args.jobId}${ext ? `.${ext}` : ''}`;
}

function inferExtension(contentType: string, filename?: string): string {
  if (filename) {
    const idx = filename.lastIndexOf('.');
    if (idx >= 0 && idx < filename.length - 1) {
      const raw = filename.slice(idx + 1).toLowerCase();
      if (/^[a-z0-9]{1,8}$/.test(raw)) return raw;
    }
  }
  const ct = contentType.toLowerCase();
  const map: Record<string, string> = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/heic': 'heic',
    'image/heif': 'heif',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'application/pdf': 'pdf',
    'application/zip': 'zip',
    'text/plain': 'txt',
    'text/markdown': 'md',
    'text/csv': 'csv',
    'application/json': 'json',
  };
  return map[ct] ?? '';
}

// Range arg shape mirrors the Cloudflare R2 binding API directly so the caller
// can parse the HTTP `Range` header once and hand the result straight through.
export type R2GetRange =
  | { offset: number; length?: number }
  | { offset: number }
  | { length: number }
  | { suffix: number };

export interface GetObjectStreamResult {
  body: ReadableStream;
  size: number;
  etag: string;
  httpMetadata: R2HTTPMetadata | undefined;
  range: R2Range | undefined;
}

// Streams an R2 object through the Worker via the binding (no S3 presign, no
// redirect). The returned `body` is a ReadableStream — callers MUST pipe it
// into the Response, never `await body` it, or we defeat the whole point.
export async function getObjectStream(
  env: Env,
  key: string,
  range?: R2GetRange,
): Promise<GetObjectStreamResult | null> {
  const obj = range ? await env.R2.get(key, { range }) : await env.R2.get(key);
  if (!obj) return null;
  return {
    body: obj.body,
    size: obj.size,
    etag: obj.etag,
    httpMetadata: obj.httpMetadata,
    range: obj.range,
  };
}

function isNotFound(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false;
  const e = err as { name?: string; $metadata?: { httpStatusCode?: number }; Code?: string };
  if (e.name === 'NotFound' || e.name === 'NoSuchKey') return true;
  if (e.Code === 'NoSuchKey' || e.Code === 'NotFound') return true;
  if (e.$metadata?.httpStatusCode === 404) return true;
  return false;
}
