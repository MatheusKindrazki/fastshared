import { createReadStream } from 'node:fs';
import { Readable } from 'node:stream';
import type { RetentionPolicy } from './options.js';

export interface DeviceRegistration {
  deviceId: string;
  deviceToken: string;
}

export interface UploadInput {
  filePath: string;
  filename: string;
  contentType: string;
  sizeBytes: number;
  sha256: string;
  retentionPolicy: RetentionPolicy;
}

export interface UploadResult {
  shortUrl: string;
  token: string;
  expiresAt: string;
  deleteAfter: string;
  linkStatus: string;
  retentionPolicy: string;
  assetId?: string;
}

export type PublicationKind = 'site' | 'pdf' | 'file';

export interface PublicationCreateBody {
  title?: string;
  kind: PublicationKind;
  filename: string;
  contentType: string;
  sizeBytes: number;
}

export interface PublicationSlot {
  id: string;
  slug: string;
  url: string;
  version: number;
  upload: {
    url: string;
    method: 'PUT';
    headers: Record<string, string>;
  };
}

export interface PublicationReady {
  id?: string;
  slug?: string;
  url: string;
  version: number;
  fileCount: number;
  totalBytes: number;
}

export type PublicationCompletion =
  | { state: 'ready'; ready: PublicationReady }
  | { state: 'processing'; retryAfterMs?: number; pollPath?: string };

export interface PublicationSummary {
  id: string;
  slug: string;
  url: string;
  title?: string;
  kind: string;
  status: string;
  version: number;
  expiresAt: string | null;
  opens7d: number;
}

export interface PublicationRevocation {
  id: string;
  status: string;
}

export interface PublicationOpenCount {
  version: number;
  count: number;
  lastOpenedAt: string | null;
}

export interface PublicationOpens {
  id: string;
  versions: PublicationOpenCount[];
}

interface UploadInstructionSingle {
  mode: 'single';
  url: string;
  method: 'PUT';
  headers: Record<string, string>;
  expiresAt: string;
}

interface UploadInstructionMultipart {
  mode: 'multipart';
  multipartUploadId: string;
  partSize: number;
  parts: Array<{ partNumber: number; url: string; method: 'PUT' }>;
  expiresAt: string;
}

type UploadInstruction = UploadInstructionSingle | UploadInstructionMultipart;

interface PresignResponse {
  uploadId?: string;
  upload?: UploadInstruction;
  shortUrl?: string;
  token?: string;
  expiresAt?: string;
  deleteAfter?: string;
  linkStatus?: string;
  retentionPolicy?: string;
  deduped?: {
    assetId: string;
    shortUrl: string;
    token: string;
    expiresAt: string;
    deleteAfter: string;
    retentionPolicy: string;
  };
}

interface CompleteResponse {
  assetId: string;
  shortUrl: string;
  token: string;
  expiresAt: string;
  deleteAfter: string;
  linkStatus: string;
  retentionPolicy: string;
}

interface ProblemBody {
  status?: number;
  code?: string;
  title?: string;
  detail?: string;
  upgradeUrl?: string;
  unpack_error?: string;
  unpackError?: string;
}

export class FastSharedHttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,
    readonly detail?: string,
    readonly upgradeUrl?: string,
    readonly unpackError?: string,
  ) {
    super(message);
  }
}

export class FastSharedApi {
  private readonly apiBaseUrl: string;
  private readonly fetchImpl: typeof fetch;

  constructor(options: { apiBaseUrl: string; fetchImpl?: typeof fetch }) {
    this.apiBaseUrl = options.apiBaseUrl.replace(/\/+$/, '');
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async registerDevice(appVersion: string): Promise<DeviceRegistration> {
    return this.requestJson<DeviceRegistration>('/v1/devices', {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ platform: 'cli', appVersion }),
    });
  }

  async uploadFile(input: UploadInput, deviceToken: string): Promise<UploadResult> {
    const presign = await this.requestJson<PresignResponse>(
      '/v1/uploads',
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          accept: 'application/json',
          authorization: `Bearer ${deviceToken}`,
        },
        body: JSON.stringify({
          clientJobId: crypto.randomUUID(),
          contentType: input.contentType,
          sizeBytes: input.sizeBytes,
          sha256: input.sha256,
          originalFilename: input.filename,
          retentionPolicy: input.retentionPolicy,
        }),
      },
    );

    if (presign.deduped) {
      return {
        assetId: presign.deduped.assetId,
        shortUrl: presign.deduped.shortUrl,
        token: presign.deduped.token,
        expiresAt: presign.deduped.expiresAt,
        deleteAfter: presign.deduped.deleteAfter,
        linkStatus: 'active',
        retentionPolicy: presign.deduped.retentionPolicy,
      };
    }

    if (!presign.uploadId || !presign.upload) {
      throw new Error('invalid presign response: missing uploadId/upload');
    }

    let usedMultipart = false;
    try {
      let multipart: { parts: Array<{ partNumber: number; eTag: string }> } | undefined;
      if (presign.upload.mode === 'multipart') {
        usedMultipart = true;
        multipart = { parts: await this.putMultipart(input.filePath, input.sizeBytes, presign.upload) };
      } else {
        await this.putSingle(input.filePath, presign.upload);
      }

      const complete = await this.requestJson<CompleteResponse>(
        `/v1/uploads/${encodeURIComponent(presign.uploadId)}/complete`,
        {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            accept: 'application/json',
            authorization: `Bearer ${deviceToken}`,
          },
          body: JSON.stringify({
            contentType: input.contentType,
            sizeBytes: input.sizeBytes,
            sha256: input.sha256,
            originalFilename: input.filename,
            ...(multipart ? { multipart } : {}),
          }),
        },
      );
      return complete;
    } catch (err) {
      if (usedMultipart) await this.abortMultipart(presign.uploadId, deviceToken).catch(() => undefined);
      else await this.markFailed(presign.uploadId, deviceToken, err).catch(() => undefined);
      throw err;
    }
  }

  async createPublication(body: PublicationCreateBody, deviceToken: string): Promise<PublicationSlot> {
    const slot = await this.requestJson<PublicationSlot>('/v1/publications', {
      method: 'POST',
      headers: jsonAuth(deviceToken),
      body: JSON.stringify(body),
    });
    return normalizeSlot(slot);
  }

  async createPublicationVersion(
    idOrSlug: string,
    body: PublicationCreateBody,
    deviceToken: string,
  ): Promise<PublicationSlot> {
    const slot = await this.requestJson<PublicationSlot>(
      `/v1/publications/${encodeURIComponent(idOrSlug)}/versions`,
      {
        method: 'POST',
        headers: jsonAuth(deviceToken),
        body: JSON.stringify(body),
      },
    );
    return normalizeSlot(slot);
  }

  async putPublicationObject(filePath: string, upload: PublicationSlot['upload']): Promise<void> {
    await this.putSingle(filePath, {
      mode: 'single',
      url: upload.url,
      method: 'PUT',
      headers: upload.headers,
      expiresAt: '',
    });
  }

  async completePublication(id: string, version: number, deviceToken: string): Promise<PublicationCompletion> {
    const response = await this.fetchImpl(this.apiUrl(`/v1/publications/${encodeURIComponent(id)}/versions/${version}/complete`), {
      method: 'POST',
      headers: {
        accept: 'application/json',
        authorization: `Bearer ${deviceToken}`,
      },
    });
    return this.readPublicationCompletion(response);
  }

  async pollPublication(pollTarget: string, deviceToken: string): Promise<PublicationCompletion> {
    const response = await this.fetchImpl(this.authorizedPollUrl(pollTarget), {
      method: 'GET',
      headers: {
        accept: 'application/json',
        authorization: `Bearer ${deviceToken}`,
      },
    });
    return this.readPublicationCompletion(response);
  }

  async claimLinkCode(code: string, deviceToken: string): Promise<{ linked: boolean; userId: string }> {
    const body = await this.requestJson<unknown>('/v1/link-codes/claim', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        accept: 'application/json',
        authorization: `Bearer ${deviceToken}`,
      },
      body: JSON.stringify({ code }),
    });
    const obj = (body ?? {}) as Record<string, unknown>;
    if (obj.linked !== true || typeof obj.userId !== 'string') {
      throw new Error('invalid link response');
    }
    return { linked: true, userId: obj.userId };
  }

  async me(deviceToken: string): Promise<{ userId: string | null; isPro: boolean }> {
    const body = await this.requestJson<unknown>('/v1/me', {
      method: 'GET',
      headers: { accept: 'application/json', authorization: `Bearer ${deviceToken}` },
    });
    const obj = (body ?? {}) as Record<string, unknown>;
    return {
      userId: typeof obj.userId === 'string' ? obj.userId : null,
      isPro: obj.isPro === true,
    };
  }

  async listPublications(deviceToken: string): Promise<PublicationSummary[]> {
    const body = await this.requestJson<unknown>('/v1/publications', {
      method: 'GET',
      headers: { accept: 'application/json', authorization: `Bearer ${deviceToken}` },
    });
    return parsePublicationList(body);
  }

  async revokePublication(idOrSlug: string, deviceToken: string): Promise<PublicationRevocation> {
    const body = await this.requestJson<unknown>(`/v1/publications/${encodeURIComponent(idOrSlug)}/revoke`, {
      method: 'POST',
      headers: { accept: 'application/json', authorization: `Bearer ${deviceToken}` },
    });
    return parseRevocation(body);
  }

  async publicationOpens(idOrSlug: string, deviceToken: string): Promise<PublicationOpens> {
    const body = await this.requestJson<unknown>(`/v1/publications/${encodeURIComponent(idOrSlug)}/opens`, {
      method: 'GET',
      headers: { accept: 'application/json', authorization: `Bearer ${deviceToken}` },
    });
    return parseOpens(body);
  }

  private async putSingle(filePath: string, upload: UploadInstructionSingle): Promise<void> {
    const response = await this.fetchImpl(upload.url, {
      method: upload.method,
      headers: upload.headers,
      body: Readable.toWeb(createReadStream(filePath)) as BodyInit,
      duplex: 'half',
    } as RequestInit & { duplex: 'half' });
    if (!response.ok) {
      throw new FastSharedHttpError(response.status, `R2 upload failed with HTTP ${response.status}`);
    }
  }

  private async putMultipart(
    filePath: string,
    sizeBytes: number,
    upload: UploadInstructionMultipart,
  ): Promise<Array<{ partNumber: number; eTag: string }>> {
    const parts: Array<{ partNumber: number; eTag: string }> = [];
    for (const part of upload.parts.slice().sort((a, b) => a.partNumber - b.partNumber)) {
      const start = (part.partNumber - 1) * upload.partSize;
      const end = Math.min(start + upload.partSize, sizeBytes) - 1;
      const length = end - start + 1;
      const response = await this.fetchImpl(part.url, {
        method: part.method,
        headers: { 'content-length': String(length) },
        body: Readable.toWeb(createReadStream(filePath, { start, end })) as BodyInit,
        duplex: 'half',
      } as RequestInit & { duplex: 'half' });
      if (!response.ok) {
        throw new FastSharedHttpError(
          response.status,
          `R2 multipart part ${part.partNumber} failed with HTTP ${response.status}`,
        );
      }
      const eTag = response.headers.get('etag');
      if (!eTag) throw new Error(`R2 multipart part ${part.partNumber} did not return an ETag`);
      parts.push({ partNumber: part.partNumber, eTag });
    }
    return parts;
  }

  private async markFailed(uploadId: string, deviceToken: string, err: unknown): Promise<void> {
    await this.requestVoid(`/v1/uploads/${encodeURIComponent(uploadId)}/fail`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${deviceToken}`,
      },
      body: JSON.stringify({
        errorCode: 'cli_upload_failed',
        detail: err instanceof Error ? err.message : String(err),
      }),
    });
  }

  private async abortMultipart(uploadId: string, deviceToken: string): Promise<void> {
    await this.requestVoid(`/v1/uploads/${encodeURIComponent(uploadId)}/abort-multipart`, {
      method: 'POST',
      headers: { authorization: `Bearer ${deviceToken}` },
    });
  }

  private apiUrl(path: string): string {
    return `${this.apiBaseUrl}${path}`;
  }

  private authorizedPollUrl(target: string): string {
    const absolute = target.startsWith('https://') || target.startsWith('http://');
    if (!absolute && !target.startsWith('/')) {
      throw new Error('publication poll URL is not on the API host');
    }
    const url = absolute ? new URL(target) : new URL(target, `${this.apiBaseUrl}/`);
    const base = new URL(this.apiBaseUrl);
    if (url.origin !== base.origin) {
      throw new Error('publication poll URL is not on the API host');
    }
    return url.toString();
  }

  private async readPublicationCompletion(response: Response): Promise<PublicationCompletion> {
    const text = await response.text();
    let body: unknown = null;
    if (text.length > 0) {
      try {
        body = JSON.parse(text) as unknown;
      } catch {
        throw new Error(`invalid publication response (${response.status})`);
      }
    }
    const record = body && typeof body === 'object' ? (body as Record<string, unknown>) : null;
    const processing = response.status === 202 || record?.status === 'processing';
    if (processing && (response.ok || response.status === 202)) {
      const retryAfterMs = readRetryAfter(response.headers.get('retry-after'), record);
      const location = response.headers.get('location');
      const pollPath = location ? this.authorizedPollUrl(location) : undefined;
      return {
        state: 'processing',
        ...(retryAfterMs !== undefined ? { retryAfterMs } : {}),
        ...(pollPath ? { pollPath } : {}),
      };
    }
    if (!response.ok || record?.status === 'failed') {
      throw problemToError(response.status, record, response.statusText);
    }
    return { state: 'ready', ready: parseReady(record) };
  }

  private async requestJson<T>(path: string, init: RequestInit): Promise<T> {
    const response = await this.fetchImpl(this.apiUrl(path), init);
    if (!response.ok) throw await this.toHttpError(response);
    return (await response.json()) as T;
  }

  private async requestVoid(path: string, init: RequestInit): Promise<void> {
    const response = await this.fetchImpl(this.apiUrl(path), init);
    if (!response.ok) throw await this.toHttpError(response);
  }

  private async toHttpError(response: Response): Promise<FastSharedHttpError> {
    const problem = (await response
      .clone()
      .json()
      .catch(() => null)) as ProblemBody | null;
    return problemToError(response.status, problem, response.statusText);
  }
}

function jsonAuth(deviceToken: string): Record<string, string> {
  return {
    'content-type': 'application/json',
    accept: 'application/json',
    authorization: `Bearer ${deviceToken}`,
  };
}

function problemToError(
  status: number,
  problem: ProblemBody | Record<string, unknown> | null,
  statusText: string,
): FastSharedHttpError {
  const record = (problem ?? {}) as Record<string, unknown>;
  const title = typeof record.title === 'string' ? record.title : statusText || 'HTTP error';
  const detail = typeof record.detail === 'string' ? record.detail : undefined;
  const code = typeof record.code === 'string' ? record.code : undefined;
  const upgradeUrl = typeof record.upgradeUrl === 'string' ? record.upgradeUrl : undefined;
  const unpackError =
    typeof record.unpack_error === 'string'
      ? record.unpack_error
      : typeof record.unpackError === 'string'
        ? record.unpackError
        : undefined;
  return new FastSharedHttpError(
    status,
    detail ? `${title}: ${detail}` : `${title} (${status})`,
    code,
    detail,
    upgradeUrl,
    unpackError,
  );
}

function normalizeSlot(slot: PublicationSlot): PublicationSlot {
  if (!slot || typeof slot.id !== 'string' || slot.id.length === 0) {
    throw new Error('invalid publication response: missing id');
  }
  if (typeof slot.slug !== 'string' || typeof slot.url !== 'string') {
    throw new Error('invalid publication response: missing slug or url');
  }
  if (!Number.isInteger(slot.version) || slot.version < 1) {
    throw new Error('invalid publication response: missing version');
  }
  if (!slot.upload || slot.upload.method !== 'PUT' || typeof slot.upload.url !== 'string') {
    throw new Error('invalid publication response: missing upload');
  }
  return {
    id: slot.id,
    slug: slot.slug,
    url: slot.url,
    version: slot.version,
    upload: {
      url: slot.upload.url,
      method: 'PUT',
      headers: stringHeaders(slot.upload.headers),
    },
  };
}

function stringHeaders(headers: Record<string, string> | undefined): Record<string, string> {
  if (!headers || typeof headers !== 'object') return {};
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(headers)) {
    if (typeof value === 'string') out[key] = value;
  }
  return out;
}

function parseReady(body: Record<string, unknown> | null): PublicationReady {
  if (!body || typeof body.url !== 'string' || body.url.length === 0) {
    throw new Error('invalid publication response: missing url');
  }
  if (typeof body.version !== 'number' || !Number.isInteger(body.version)) {
    throw new Error('invalid publication response: missing version');
  }
  if (typeof body.fileCount !== 'number' || !Number.isInteger(body.fileCount) || body.fileCount < 0) {
    throw new Error('invalid publication response: missing fileCount');
  }
  if (typeof body.totalBytes !== 'number' || !Number.isInteger(body.totalBytes) || body.totalBytes < 0) {
    throw new Error('invalid publication response: missing totalBytes');
  }
  return {
    url: body.url,
    version: body.version,
    fileCount: body.fileCount,
    totalBytes: body.totalBytes,
    ...(typeof body.id === 'string' ? { id: body.id } : {}),
    ...(typeof body.slug === 'string' ? { slug: body.slug } : {}),
  };
}

function readRetryAfter(header: string | null, body: Record<string, unknown> | null): number | undefined {
  if (header) {
    const seconds = Number(header);
    if (Number.isFinite(seconds) && seconds >= 0) return Math.round(seconds * 1000);
    const when = Date.parse(header);
    if (Number.isFinite(when)) return Math.max(0, when - Date.now());
  }
  if (body && typeof body.retryAfterMs === 'number' && Number.isFinite(body.retryAfterMs) && body.retryAfterMs >= 0) {
    return body.retryAfterMs;
  }
  return undefined;
}

function parsePublicationList(body: unknown): PublicationSummary[] {
  const rows = Array.isArray(body)
    ? body
    : body && typeof body === 'object' && Array.isArray((body as { publications?: unknown }).publications)
      ? (body as { publications: unknown[] }).publications
      : undefined;
  if (!rows) throw new Error('invalid publication list');
  return rows.map(parsePublicationSummary);
}

function parsePublicationSummary(value: unknown): PublicationSummary {
  if (!value || typeof value !== 'object') throw new Error('invalid publication list');
  const item = value as Record<string, unknown>;
  const id = requiredString(item.id, 'id');
  const slug = requiredString(item.slug, 'slug');
  const url = requiredString(item.url, 'url');
  const kind = requiredString(item.kind, 'kind');
  const status = requiredString(item.status, 'status');
  const version = requiredInt(item.version, 'version');
  const opensRaw = item.opens7d ?? item.opensLast7d ?? item.opens_7d;
  const opens7d = requiredInt(opensRaw, 'opens7d');
  const expiresRaw = item.expiresAt !== undefined ? item.expiresAt : item.expires_at;
  const expiresAt = expiresRaw === null || expiresRaw === undefined ? null : requiredString(expiresRaw, 'expiresAt');
  const title = typeof item.title === 'string' ? item.title : undefined;
  return {
    id,
    slug,
    url,
    kind,
    status,
    version,
    expiresAt,
    opens7d,
    ...(title ? { title } : {}),
  };
}

function parseRevocation(body: unknown): PublicationRevocation {
  if (!body || typeof body !== 'object') throw new Error('invalid revoke response');
  const item = body as Record<string, unknown>;
  return {
    id: requiredString(item.id, 'id'),
    status: typeof item.status === 'string' ? item.status : 'revoked',
  };
}

function parseOpens(body: unknown): PublicationOpens {
  if (!body || typeof body !== 'object') throw new Error('invalid opens response');
  const item = body as Record<string, unknown>;
  if (!Array.isArray(item.versions)) throw new Error('invalid opens response: missing versions');
  return {
    id: requiredString(item.id, 'id'),
    versions: item.versions.map((version) => {
      if (!version || typeof version !== 'object') throw new Error('invalid opens response');
      const row = version as Record<string, unknown>;
      const last = row.lastOpenedAt ?? row.last_opened_at;
      return {
        version: requiredInt(row.version, 'version'),
        count: requiredInt(row.count, 'count'),
        lastOpenedAt: last === null || last === undefined ? null : requiredString(last, 'lastOpenedAt'),
      };
    }),
  };
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`invalid publication response: missing ${field}`);
  }
  return value;
}

function requiredInt(value: unknown, field: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw new Error(`invalid publication response: missing ${field}`);
  }
  return value;
}
